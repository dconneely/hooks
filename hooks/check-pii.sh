#!/bin/sh
#
# Pre-commit hook: fail if the staged diff adds personal details (the checks
# below), except git/config's `name =` and `email =` lines and a decision
# record's `decision-makers:` line (AGENTS.md says why), and a hook's `repo:`
# URL in .pre-commit-config.yaml, whose owner is a third party whose handle
# can contain the same words as the committer's name. Derived patterns come
# from Git config and the OS at commit time, and optional machine-local
# patterns live in ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/pii-patterns
# (plain data, never committed), so keep this file's examples abstract.
# Gitleaks covers secrets, not names or email addresses.
#
# `--commit-msg <file>` checks a commit message instead.

set -e

if [ "${1-}" = --commit-msg ]; then
    msg_file="$2"
    what="commit message"
else
    msg_file=""
    what="staged diff"
fi

# The text to check. For a commit: the added lines, and the paths of added,
# copied or renamed files. Added lines are `+` lines after a hunk's `@@`,
# which excludes `+++` headers but keeps an added line starting with `+`.
# The diff's `+` is stripped, or "@FILE.md" would look like an email
# address. In git/config, only `name =` and `email =` are skipped, in any
# section (a hunk doesn't say which); in docs/decisions/*.md, only
# `decision-makers:`; in .pre-commit-config.yaml, only a `repo:` line that
# holds nothing but an https URL without `@`, so a comment or credentials on
# it are still checked. For a message: what Git keeps, without
# "#" lines or what follows `git commit -v`'s scissors line.
# --no-ext-diff, the prefixes and core.quotePath=false stop Git config
# changing the diff: an external tool, diff.mnemonicPrefix (verified), or
# octal-escaped paths.
candidate_text() {
    if [ -n "$msg_file" ]; then
        sed '/^# -\{24\} >8 -\{24\}$/,$d' "$msg_file" | grep -v '^#'
    else
        git -c core.quotePath=false diff --cached --no-ext-diff --src-prefix=a/ --dst-prefix=b/ |
            awk '/^diff --git /{h=1; cfg=($0 ~ / b\/git\/config$/)
                    adr=($0 ~ / b\/docs\/decisions\/[^\/]+\.md$/)
                    hooks=($0 ~ / b\/\.pre-commit-config\.yaml$/); next}
                /^@@/{h=0; next}
                cfg && /^\+[ \t]*(name|email)[ \t]*=/{next}
                adr && /^\+decision-makers:/{next}
                hooks && /^\+[ \t]*(-[ \t]+)?repo:[ \t]*https:\/\/[^ \t@]+[ \t]*$/{next}
                !h && /^\+/{print substr($0, 2)}'
        git -c core.quotePath=false diff --cached --name-only --diff-filter=ACR
    fi
}

# `|| true`: grep -v exits 1 for a message that is all comment lines.
text=$(candidate_text) || true
[ -n "$text" ] || exit 0
fail=0

# Reports the lines of $text matching grep options and pattern $2...,
# described by $1. Exit status > 1 (for example an invalid regex in the local
# checklist) fails closed instead of passing silently.
check() {
    desc=$1
    shift
    set +e
    matches=$(printf '%s\n' "$text" | grep "$@")
    status=$?
    set -e
    if [ "$status" -eq 0 ]; then
        echo "check-pii: $what $desc:" >&2
        echo "$matches" >&2
        fail=1
    elif [ "$status" -gt 1 ]; then
        echo "check-pii: grep failed while checking $desc (exit $status)" >&2
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

# (c) the OS username, ignoring case: the Windows profile folder's name,
# `id -un` and $USER, which can differ on Windows
usernames=""
if [ -n "${USERPROFILE:-}" ]; then
    usernames=$(basename "$(cygpath -u "$USERPROFILE" 2>/dev/null || printf '%s' "$USERPROFILE")" 2>/dev/null || true)
fi
usernames="$usernames $(id -un 2>/dev/null || true) ${USER:-}"
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

# (d) the machine's hostname, ignoring case. Try `hostname` first (present on
# Windows, macOS and Linux), falling back to POSIX `uname -n`; strip Windows
# CR. Skip 1-2 character and generic hostnames that match ordinary text; if
# the short label is checked, it also matches the full name.
host_raw=$(hostname 2>/dev/null || uname -n 2>/dev/null || true)
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

# (e) any path into a user-home tree (Windows' or macOS's Users, Linux's
# home), in any spelling and with any name. No literal example, and the
# slashes are bracketed, so this line can't match itself.
check "contains a path into a user-home directory" \
    -i -E -- '[/\\]Users[/\\]|/home[/]'

# (f) optional machine-local checklist, never committed. Plain text, one entry
# per line, `#` comments and blank lines ignored. Lines default to
# case-insensitive fixed strings; prefix `regex:` for a case-insensitive
# extended regular expression. Batched with `grep -f` so Windows MSYS2 forks
# at most twice regardless of list length.
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    pii_file="$XDG_CONFIG_HOME/dotfiles/pii-patterns"
elif [ -n "${HOME:-}" ]; then
    pii_file="$HOME/.config/dotfiles/pii-patterns"
else
    pii_file=""
fi
if [ -n "$pii_file" ] && [ -f "$pii_file" ] && [ -r "$pii_file" ]; then
    pii_tmp=$(mktemp -d)
    trap 'rm -rf "$pii_tmp"' EXIT HUP INT TERM
    fixed_file="$pii_tmp/fixed"
    regex_file="$pii_tmp/regex"
    : > "$fixed_file"
    : > "$regex_file"
    cr=$(printf '\r')
    tab=$(printf '\t')
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%"$cr"}
        while :; do
            case "$line" in
                " "* | "$tab"*) line=${line#?} ;;
                *) break ;;
            esac
        done
        while :; do
            case "$line" in
                *" " | *"$tab") line=${line%?} ;;
                *) break ;;
            esac
        done
        case "$line" in
            "" | \#*) continue ;;
            regex:*)
                pat=${line#regex:}
                while :; do
                    case "$pat" in
                        " "* | "$tab"*) pat=${pat#?} ;;
                        *) break ;;
                    esac
                done
                [ -n "$pat" ] && printf '%s\n' "$pat" >> "$regex_file"
                ;;
            *)
                printf '%s\n' "$line" >> "$fixed_file"
                ;;
        esac
    done < "$pii_file"
    if [ -s "$fixed_file" ]; then
        check "matches local PII checklist (pii-patterns)" -i -F -f "$fixed_file"
    fi
    if [ -s "$regex_file" ]; then
        check "matches local PII checklist (pii-patterns regex)" -i -E -f "$regex_file"
    fi
fi

exit $fail
