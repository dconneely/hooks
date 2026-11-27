#!/bin/sh
#
# check-pii: fail if text on its way into a repository holds personal
# details. The patterns are derived at run time from Git and the OS, plus an
# optional machine-local file that is never committed, so keep this file's
# examples abstract. Gitleaks covers secrets, not names or email addresses.
#
# Usage: check-pii.sh [OPTION]... [MODE] [FILE]...
#
# Modes (the last one given wins):
#   (none)              the staged diff's added lines and new paths
#   --commit-msg FILE   a commit message
#   --files FILE...     the whole content and the paths of the files
#   --history           every added line and new path in `git log -p --all`,
#                       and every commit message
#
# Options:
#   --skip-line PATH:LINE  skip a line matching the ERE LINE in a file whose
#                          whole path matches the ERE PATH (split at the
#                          first `:`); repeatable. Applies to file content in
#                          every mode, never to paths or messages.
#   --no-default-skips     drop the built-in skips (see default_skips below)
#   --no-history-names     don't check the names of the repository's
#                          committers
#
# Exit status: 0 nothing found, 1 something found or a check failed to run,
# 2 a usage error.

set -e

usage() {
    echo "check-pii: $1" >&2
    exit 2
}

nl='
'
mode="diff"
skips=""
default_skips=1
history_names=1
while [ $# -gt 0 ]; do
    case "$1" in
        --commit-msg) mode=msg ;;
        --files) mode=files ;;
        --history) mode=history ;;
        --skip-line | --skip-line=*)
            if [ "$1" = --skip-line ]; then
                [ $# -ge 2 ] || usage "--skip-line needs PATH:LINE"
                skip=$2
                shift
            else
                skip=${1#--skip-line=}
            fi
            case "$skip" in
                *:*) skips="$skips$skip$nl" ;;
                *) usage "--skip-line needs PATH:LINE, got '$skip'" ;;
            esac
            ;;
        --no-default-skips) default_skips=0 ;;
        --no-history-names) history_names=0 ;;
        --)
            shift
            break
            ;;
        -*) usage "unknown option $1" ;;
        *) break ;;
    esac
    shift
done
if [ "$mode" = msg ]; then
    [ $# -ge 1 ] || usage "--commit-msg needs the message file"
    msg_file=$1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
# Each record is a location in loc and the text to check on the same line
# of text; the awk programs below write both through emit().
CHECK_PII_LOC="$work/loc"
CHECK_PII_TEXT="$work/text"
CHECK_PII_SKIPS="$work/skips"
CHECK_PII_ALLOW="$work/allow"
export CHECK_PII_LOC CHECK_PII_TEXT CHECK_PII_SKIPS CHECK_PII_ALLOW
: > "$CHECK_PII_LOC"
: > "$CHECK_PII_TEXT"
: > "$CHECK_PII_SKIPS"
: > "$CHECK_PII_ALLOW"

# default_skips: structural lines every consumer needs. A hook's `repo:` URL
# in .pre-commit-config.yaml holding nothing but an https URL without `@`
# (every consumer pins this repository, and a third party's handle can share
# a word with the committer's name), so a comment or credentials on the line
# are still checked; and doc-kit's `decision-makers:` front matter. Bracket
# classes, not `\t`: awk reads these from a file, where `\t` support varies.
if [ "$default_skips" -eq 1 ]; then
    cat >> "$CHECK_PII_SKIPS" << 'EOF'
\.pre-commit-config\.yaml:^[[:blank:]]*(-[[:blank:]]+)?repo:[[:blank:]]*https://[^[:blank:]@]+[[:blank:]]*$
docs/decisions/[^/]+\.md:^decision-makers:
EOF
fi
printf '%s' "$skips" >> "$CHECK_PII_SKIPS"

# Shared by the record writers. The EREs come from a file and the paths
# from ENVIRON, never from `awk -v`, which would treat their backslashes as
# escape sequences. A skip's path ERE is anchored to the whole path.
awk_lib='
function load_skips(   line, i) {
    while ((getline line < ENVIRON["CHECK_PII_SKIPS"]) > 0) {
        if (line == "") continue
        i = index(line, ":")
        nskips++
        skip_path[nskips] = "^(" substr(line, 1, i - 1) ")$"
        skip_line[nskips] = substr(line, i + 1)
    }
}
function emit(loc, line) {
    print loc >> ENVIRON["CHECK_PII_LOC"]
    print line >> ENVIRON["CHECK_PII_TEXT"]
}
function emit_line(prefix, path, n, line,   k) {
    for (k = 1; k <= nskips; k++)
        if (path ~ skip_path[k] && line ~ skip_line[k]) return
    emit(prefix path ":" n, line)
}
function diff_path(header,   p) {
    p = header
    sub(/.* b\//, "", p)
    return p
}
'

# Diff lines: added lines are `+` lines after a hunk's `@@`, which excludes
# the `+++` header but keeps an added line whose text starts with `+`; the
# `+` is stripped, or "@FILE.md" would look like an email address. The line
# number comes from the hunk's `+N` and counts added and context lines. Git
# ends a `+++` path containing a space with a tab. --no-ext-diff, the
# prefixes and core.quotePath=false stop Git config changing the diff: an
# external tool, diff.mnemonicPrefix (verified), or octal-escaped paths.
diff_awk='
/^diff --git / { h = 1; path = diff_path($0); next }
h && /^\+\+\+ b\// { path = substr($0, 7); sub(/\t$/, "", path); next }
/^@@/ { h = 0; s = $0; sub(/^@@ -[0-9,]+ \+/, "", s); n = s + 0; next }
h { next }
/^\+/ { emit_line(prefix, path, n, substr($0, 2)); n++; next }
/^ / { n++ }
'

case "$mode" in
    diff)
        git -c core.quotePath=false diff --cached --no-ext-diff --no-color \
            --src-prefix=a/ --dst-prefix=b/ |
            awk "$awk_lib"'BEGIN { load_skips(); prefix = "" }'"$diff_awk"
        git -c core.quotePath=false diff --cached --name-only --diff-filter=ACR |
            awk "$awk_lib"'{ emit($0 " (path)", $0) }'
        ;;
    msg)
        # What Git keeps: no `#` lines, nothing below `git commit -v`'s
        # scissors line.
        awk "$awk_lib"'
            $0 == "# ------------------------ >8 ------------------------" { exit }
            /^#/ { next }
            { sub(/\r$/, ""); emit("commit message:" NR, $0) }' "$msg_file"
        ;;
    files)
        [ $# -gt 0 ] || exit 0
        # `./` stops awk reading a path containing `=` as an assignment, or
        # `-` as standard input.
        for f in "$@"; do
            case "$f" in
                /*) set -- "$@" "$f" ;;
                *) set -- "$@" "./$f" ;;
            esac
            shift
        done
        awk "$awk_lib"'
            BEGIN {
                load_skips()
                for (i = 1; i < ARGC; i++) {
                    p = ARGV[i]; sub(/^\.\//, "", p)
                    emit(p " (path)", p)
                }
            }
            FNR == 1 { path = FILENAME; sub(/^\.\//, "", path) }
            { sub(/\r$/, ""); emit_line("", path, FNR, $0) }' "$@"
        ;;
    history)
        # Each commit starts with SOH, its short hash and message, and a lone
        # SOH line ends the message (verified): `%B` ends with a newline.
        # Merges show no diff. A new file's path comes from `new file mode`,
        # since an empty file has no `+++` line, and a rename's from
        # `rename to`.
        git -c core.quotePath=false log --all -p --no-ext-diff --no-color \
            --src-prefix=a/ --dst-prefix=b/ --format='%x01%h%n%B%x01' |
            awk "$awk_lib"'
                BEGIN { load_skips(); soh = sprintf("%c", 1) }
                inmsg && $0 == soh { inmsg = 0; next }
                inmsg { m++; emit(sha " commit message:" m, $0); next }
                substr($0, 1, 1) == soh {
                    sha = substr($0, 2); prefix = sha " "; inmsg = 1; m = 0; h = 0; next
                }
                h && /^new file mode/ { emit(prefix path " (path)", path); next }
                h && /^(rename|copy) to / {
                    p = $0; sub(/^(rename|copy) to /, "", p)
                    emit(prefix p " (path)", p); next
                }'"$diff_awk"
        ;;
esac

[ -s "$CHECK_PII_TEXT" ] || exit 0
fail=0

# The machine-local patterns, never committed: a plain line rejects a
# case-insensitive fixed string, `regex:` an extended regular expression
# (also case-insensitive), and `!` allows a fixed string by removing it
# before any check runs. `#` lines and blank lines are ignored. The file is
# named after the tool, as XDG expects.
fixed_file="$work/fixed"
regex_file="$work/regex"
: > "$fixed_file"
: > "$regex_file"
config_home=${XDG_CONFIG_HOME:-}
if [ -z "$config_home" ] && [ -n "${HOME:-}" ]; then
    config_home=$HOME/.config
fi
cr=$(printf '\r')
tab=$(printf '\t')
trim_leading() {
    trimmed=$1
    while :; do
        case "$trimmed" in
            " "* | "$tab"*) trimmed=${trimmed#?} ;;
            *) break ;;
        esac
    done
}
pii_file=$config_home/check-pii/patterns
if [ -n "$config_home" ] && [ -f "$pii_file" ] && [ -r "$pii_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%"$cr"}
        trim_leading "$line"
        line=$trimmed
        while :; do
            case "$line" in
                *" " | *"$tab") line=${line%?} ;;
                *) break ;;
            esac
        done
        case "$line" in
            "" | \#*) continue ;;
            regex:*)
                trim_leading "${line#regex:}"
                [ -z "$trimmed" ] || printf '%s\n' "$trimmed" >> "$regex_file"
                ;;
            !*)
                trim_leading "${line#!}"
                [ -z "$trimmed" ] || printf '%s\n' "$trimmed" >> "$CHECK_PII_ALLOW"
                ;;
            *) printf '%s\n' "$line" >> "$fixed_file" ;;
        esac
    done < "$pii_file"
fi

# Allow entries: remove each occurrence, ignoring case, so the rest of the
# line is still checked. Findings still show the line as written.
check_file=$CHECK_PII_TEXT
if [ -s "$CHECK_PII_ALLOW" ]; then
    check_file="$work/checked"
    awk '
        BEGIN {
            while ((getline a < ENVIRON["CHECK_PII_ALLOW"]) > 0) allow[++n] = tolower(a)
        }
        {
            s = $0
            for (k = 1; k <= n; k++) {
                out = ""; ls = tolower(s); len = length(allow[k])
                while ((p = index(ls, allow[k])) > 0) {
                    out = out substr(s, 1, p - 1)
                    s = substr(s, p + len); ls = substr(ls, p + len)
                }
                s = out s
            }
            print s
        }' "$CHECK_PII_TEXT" > "$check_file"
fi

# Reports each record matching grep options and pattern $2..., described by
# $1, as `location: description` and then the line. Exit status > 1 (for
# example an invalid regex in the patterns file) fails closed instead of
# passing silently.
check() {
    CHECK_PII_DESC=$1
    export CHECK_PII_DESC
    shift
    set +e
    grep -n "$@" "$check_file" > "$work/matches"
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
        awk '
            { want[substr($0, 1, index($0, ":") - 1)] = 1 }
            END {
                while ((getline loc < ENVIRON["CHECK_PII_LOC"]) > 0) {
                    getline line < ENVIRON["CHECK_PII_TEXT"]
                    i++
                    if (i in want) {
                        print loc ": " ENVIRON["CHECK_PII_DESC"]
                        print "    " line
                    }
                }
            }' "$work/matches" >&2
        fail=1
    elif [ "$status" -gt 1 ]; then
        echo "check-pii: grep failed while checking that it $CHECK_PII_DESC (exit $status)" >&2
        fail=1
    fi
}

# (a) anything email-shaped
check "contains what looks like an email address" \
    -E -- '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# (b) each word of the committer's name, ignoring case
name=$(git config user.name || true)
# shellcheck disable=SC2086
for word in $name; do
    check "mentions '$word' (from git user.name)" -i -F -- "$word"
done

# (c) each word of every other author's and committer's name in the history,
# ignoring case, batched into one grep. Skipped: bots, one-word names
# (handles, "GitHub", "unknown"), words under three letters, and words with
# digits or punctuation other than `-` and `'`, which match ordinary text.
if [ "$history_names" -eq 1 ]; then
    CHECK_PII_NAME=$name
    export CHECK_PII_NAME
    { git log --all --format='%an%n%cn' 2> /dev/null || true; } |
        awk '
            BEGIN {
                n = split(tolower(ENVIRON["CHECK_PII_NAME"]), own, " ")
                for (i = 1; i <= n; i++) seen[own[i]] = 1
            }
            /\[bot\]/ || NF < 2 { next }
            {
                for (i = 1; i <= NF; i++) {
                    w = $i
                    if (length(w) < 3 || w ~ /[][0-9!"#$%&()*+,.\/:;<=>?@\\^_`{|}~]/) continue
                    lw = tolower(w)
                    if (lw in seen) continue
                    seen[lw] = 1
                    print w
                }
            }' > "$work/names"
    if [ -s "$work/names" ]; then
        check "mentions a word of a committer's name (from git log)" -i -F -f "$work/names"
    fi
fi

# (d) the OS username, ignoring case: the Windows profile folder's name,
# `id -un` and $USER, which can differ on Windows
usernames=""
if [ -n "${USERPROFILE:-}" ]; then
    usernames=$(basename "$(cygpath -u "$USERPROFILE" 2> /dev/null || printf '%s' "$USERPROFILE")" 2> /dev/null || true)
fi
usernames="$usernames $(id -un 2> /dev/null || true) ${USER:-}"
checked=" "
# shellcheck disable=SC2086
for username in $usernames; do
    case "$checked" in *" $username "*) continue ;; esac
    # Generic names identify nobody, and "root" would match repo_root
    case "$username" in
        root | admin | administrator | user | guest | runner | ubuntu | vagrant) continue ;;
    esac
    checked="$checked$username "
    check "mentions '$username' (OS username)" -i -F -- "$username"
done

# (e) the machine's hostname, ignoring case. Try `hostname` first (present on
# Windows, macOS and Linux), falling back to POSIX `uname -n`; strip Windows
# CR. Skip 1-2 character and generic hostnames that match ordinary text; if
# the short label is checked, it also matches the full name.
host_raw=$(hostname 2> /dev/null || uname -n 2> /dev/null || true)
host_raw=$(printf '%s' "$host_raw" | tr -d '\r\n')
if [ -n "$host_raw" ]; then
    host_short=${host_raw%%.*}
    host_checked=" "
    for host_part in "$host_short" "$host_raw"; do
        [ -n "$host_part" ] || continue
        case "$host_checked" in *" $host_part "*) continue ;; esac
        host_checked="$host_checked$host_part "
        case "$host_part" in ? | ??) continue ;; esac
        host_lc=$(printf '%s' "$host_part" | tr '[:upper:]' '[:lower:]')
        case "$host_lc" in
            localhost | localhost.localdomain | localdomain | \
                ubuntu | debian | fedora | arch | alpine | \
                linux | darwin | macos | windows | runner | \
                desktop | laptop | server | host | machine | workstation | \
                dev | test | ci)
                continue
                ;;
        esac
        check "mentions '$host_part' (hostname)" -i -F -- "$host_part"
        break
    done
fi

# (f) any path into a user-home tree (Windows' or macOS's Users, Linux's
# home), in any spelling and with any name. No literal example, and the
# slashes are bracketed, so this line can't match itself.
home_ere='[/\\]Users[/\\]|/home[/]'
check "contains a path into a user-home directory" -i -E -- "$home_ere"

# (g) the directory holding the checkout, in each spelling: a clone outside
# the home directory escapes (f), yet its path shows the disk layout and
# often the owner's handle. `X:/a/b` also gives `X:\a\b` and MSYS2's
# `/x/a/b`; on Windows, a POSIX path also gives cygpath's forms. A directory
# fewer than two levels below the root is skipped, since its spelling also
# occurs inside ordinary paths, and one under a home directory is left to
# (f).
top=$(git rev-parse --show-toplevel 2> /dev/null || true)
top=${top%"$cr"}
parent=${top%/*}
case "$(uname -s 2> /dev/null)" in
    MINGW* | MSYS* | CYGWIN*) windows=1 ;;
    *) windows=0 ;;
esac
drive=""
rest=$parent
case "$parent" in
    [A-Za-z]:/*)
        drive=${parent%%:*}
        rest=${parent#?:}
        ;;
    /[A-Za-z]/*)
        if [ "$windows" -eq 1 ]; then
            rest=${parent#/?}
            drive=${parent#/}
            drive=${drive%%/*}
        fi
        ;;
esac
# Counted in the shell: each fork costs tens of milliseconds under MSYS2
depth=0
left=$rest
while :; do
    while :; do
        case "$left" in
            /*) left=${left#/} ;;
            *) break ;;
        esac
    done
    [ -n "$left" ] || break
    depth=$((depth + 1))
    case "$left" in
        */*) left=${left#*/} ;;
        *) left="" ;;
    esac
done
if [ -n "$top" ] && [ "$depth" -ge 2 ]; then
    {
        if [ -n "$drive" ]; then
            printf '%s\n' "$drive:$rest"
            printf '%s\n' "$drive:$(printf '%s' "$rest" | tr / '\\')"
            printf '%s\n' "/$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')$rest"
        else
            printf '%s\n' "$parent"
            if [ "$windows" -eq 1 ]; then
                cygpath -m "$parent" 2> /dev/null || true
                cygpath -w "$parent" 2> /dev/null || true
            fi
        fi
    } > "$work/spellings"
    # Per spelling: cygpath's forms of a POSIX path are under the home
    # directory when MSYS2 is installed there (verified with Scoop's MSYS2).
    grep -v -i -E -- "$home_ere" "$work/spellings" > "$work/parent" || true
    if [ -s "$work/parent" ]; then
        check "contains the checkout's parent directory" -i -F -f "$work/parent"
    fi
fi

# (h) the machine-local patterns, batched with `grep -f` so Windows MSYS2
# forks at most twice regardless of the file's length
if [ -s "$fixed_file" ]; then
    check "matches a local pattern (check-pii/patterns)" -i -F -f "$fixed_file"
fi
if [ -s "$regex_file" ]; then
    check "matches a local pattern (check-pii/patterns regex)" -i -E -f "$regex_file"
fi

exit $fail
