#!/bin/sh

set -e

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
unit_init "$0"

# hooks/check-pii.sh --commit-msg: the checks, run on a message file.
# Runs in a scratch repo with a made-up identity, stubbed hostname and empty
# XDG config dir, never the real machine's identity or local checklist. The
# strings that should trip it are assembled at run time, so this file itself
# never contains an email address or a home-directory path.
prepo="$tmp/pii-repo"
git init -q "$prepo"
git -C "$prepo" config user.name "Jane Example"
mkdir -p "$tmp/empty-xdg" "$tmp/hoststub"
printf '%s\n' '#!/bin/sh' 'echo box-example.local' > "$tmp/hoststub/hostname"
chmod +x "$tmp/hoststub/hostname"
pii() {
    printf '%s\n' "$1" > "$tmp/msg.txt"
    (cd "$prepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null)
}
at="@"
slash="/"

# a clean message passes
check "check-pii msg: clean message passes" pii "fix: tidy the installer"

# Each kind of personal information fails.
if pii "thanks to jane${at}example.org"; then r=passed; else r=failed; fi
check "check-pii msg: email-shaped text fails" [ "$r" = failed ]
if pii "reviewed by example"; then r=passed; else r=failed; fi
check "check-pii msg: a word of user.name fails (any case)" [ "$r" = failed ]
# ...including inside a longer word: a username or handle is often built
# from the name (here, "jexample")
if pii "see github.com/jexample/x"; then r=passed; else r=failed; fi
check "check-pii msg: a word of user.name inside a longer word fails" [ "$r" = failed ]
if pii "copied from tester's machine"; then r=passed; else r=failed; fi
check "check-pii msg: the OS username fails" [ "$r" = failed ]
# ...and off Windows, where there's no USERPROFILE: `id -un` and $USER.
# `id` is a stub answering with a made-up name: the real one depends on
# the machine, and CI's ("runner") is one of the generic names the hook
# deliberately skips.
mkdir -p "$tmp/idstub"
printf '%s\n' '#!/bin/sh' 'echo idstubuser' > "$tmp/idstub/id"
chmod +x "$tmp/idstub/id"
printf '%s\n' "copied from idstubuser's machine" > "$tmp/msg.txt"
if (cd "$prepo" && env -u USERPROFILE XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/idstub:$tmp/hoststub:$PATH" sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii msg: username from id -un fails without USERPROFILE" [ "$r" = failed ]
printf '%s\n' "copied from otheruser's machine" > "$tmp/msg.txt"
if (cd "$prepo" && env -u USERPROFILE XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" USER=otheruser sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii msg: \$USER fails without USERPROFILE" [ "$r" = failed ]
# ...but a generic account name like root isn't checked: it identifies
# nobody, and would block ordinary code like repo_root
printf '%s\n' "fix: repo_root and resolve_root" > "$tmp/msg.txt"
if (cd "$prepo" && env -u USERPROFILE XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" USER=root sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii msg: a generic account name (root) isn't checked" [ "$r" = passed ]
if pii "copied from BOX-EXAMPLE"; then r=passed; else r=failed; fi
check "check-pii msg: local hostname fails (any case)" [ "$r" = failed ]
mkdir -p "$tmp/hostlocal" "$tmp/hostfqdn"
printf '%s\n' '#!/bin/sh' 'echo localhost' > "$tmp/hostlocal/hostname"
printf '%s\n' '#!/bin/sh' 'echo host.corp.invalid' > "$tmp/hostfqdn/hostname"
chmod +x "$tmp/hostlocal/hostname" "$tmp/hostfqdn/hostname"
printf '%s\n' "bind localhost only" > "$tmp/msg.txt"
if (cd "$prepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hostlocal:$PATH" USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii msg: generic hostname (localhost) isn't checked" [ "$r" = passed ]
printf '%s\n' "connect to host.corp.invalid" > "$tmp/msg.txt"
if (cd "$prepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hostfqdn:$PATH" USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii msg: FQDN fails even when short label is generic" [ "$r" = failed ]
if pii "moved ${slash}home${slash}someone${slash}x"; then r=passed; else r=failed; fi
check "check-pii msg: a home-directory path fails" [ "$r" = failed ]

# Optional machine-local patterns file under XDG_CONFIG_HOME/check-pii/patterns
mkdir -p "$tmp/local-xdg/check-pii"
cr=$(printf '\r')
cat > "$tmp/local-xdg/check-pii/patterns" <<EOF
# Comments and blank lines are ignored
   # Indented comment too

  Acme-Widget${cr}
regex: proj-[0-9]{4}${cr}
regex:
EOF
pii_local() {
    printf '%s\n' "$1" > "$tmp/msg.txt"
    (cd "$prepo" && XDG_CONFIG_HOME="$tmp/local-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null)
}
check "check-pii local list: clean message passes" pii_local "fix: tidy the installer"
if pii_local "deploy for acme-widget"; then r=passed; else r=failed; fi
check "check-pii local list: fixed entry fails (any case, CRLF)" [ "$r" = failed ]
if pii_local "refs PROJ-4821"; then r=passed; else r=failed; fi
check "check-pii local list: regex entry fails" [ "$r" = failed ]
mkdir -p "$tmp/bad-xdg/check-pii"
printf '%s\n' 'regex: [unclosed' > "$tmp/bad-xdg/check-pii/patterns"
printf '%s\n' "fix: clean text" > "$tmp/msg.txt"
if (cd "$prepo" && XDG_CONFIG_HOME="$tmp/bad-xdg" PATH="$tmp/hoststub:$PATH" USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii local list: invalid regex fails closed" [ "$r" = failed ]

# Git's comment lines and anything below the scissors line are ignored
check "check-pii msg: comments and scissors section ignored" pii "fix: tidy
# Jane Example, jane${at}example.org
# ------------------------ >8 ------------------------
${slash}home${slash}someone"

# `!` entries in the patterns file allow a string by removing it before the
# checks; the file's other entries still apply
mkdir -p "$tmp/new-xdg/check-pii"
cat > "$tmp/new-xdg/check-pii/patterns" <<EOF
Acme-Widget
!JaneExampleson
  ! Example-Corp${cr}
!
EOF
pii_new() {
    printf '%s\n' "$1" > "$tmp/msg.txt"
    (cd "$prepo" && XDG_CONFIG_HOME="$tmp/new-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null)
}
if pii_new "deploy for acme-widget"; then r=passed; else r=failed; fi
check "check-pii patterns: an entry beside allow entries fails" [ "$r" = failed ]
check "check-pii patterns: an allowed string passes (any case)" \
    pii_new "see github.com/janeexampleson/linter and EXAMPLE-CORP"
if pii_new "github.com/JaneExampleson/linter, by Jane"; then r=passed; else r=failed; fi
check "check-pii patterns: the rest of a line with an allowed string is checked" [ "$r" = failed ]

# Options come before the message file, as prek passes a hook's args
printf '%s\n' "fix: tidy the installer" > "$tmp/msg.txt"
check "check-pii msg: options before the message file" \
    sh -c 'cd "$1" && XDG_CONFIG_HOME="$2" sh "$3" --commit-msg --skip-line "x:y" --no-default-skips "$4" 2>/dev/null' \
    sh "$prepo" "$tmp/empty-xdg" "$repo_dir/hooks/check-pii.sh" "$tmp/msg.txt"
if sh "$repo_dir/hooks/check-pii.sh" --skip-line nocolon --commit-msg "$tmp/msg.txt" 2>/dev/null; then r=0; else r=$?; fi
check "check-pii: a --skip-line without a colon is a usage error" [ "$r" = 2 ]
if sh "$repo_dir/hooks/check-pii.sh" --bogus 2>/dev/null; then r=0; else r=$?; fi
check "check-pii: an unknown option is a usage error" [ "$r" = 2 ]

# hooks/check-pii.sh on the staged diff (its pre-commit mode), in the same
# scratch repo. Arguments go to the hook.
piidiff() {
    (cd "$prepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" "$@" 2>/dev/null)
}
# piidiff_err: the hook's findings, moved to standard output
piidiff_err() {
    (cd "$prepo" && { XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" >/dev/null; } 2>&1) || true
}
config_skip='git/config:^[[:blank:]]*(name|email)[[:blank:]]*='
# stage_only <file> <content>: the scratch repo's index holds just this file
stage_only() {
    git -C "$prepo" read-tree --empty
    mkdir -p "$(dirname "$prepo/$1")"
    printf '%s\n' "$2" > "$prepo/$1"
    git -C "$prepo" -c core.autocrlf=false add "$1"
    rm "$prepo/$1"
}

# a clean staged file passes
stage_only notes.txt "fix: tidy the installer"
check "check-pii diff: clean file passes" piidiff

# an added line whose own text starts with "+" is still checked
stage_only notes.txt "+ reviewed by example"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: an added line starting with + is checked" [ "$r" = failed ]

# so is a new file's name, even with clean content
stage_only jexample.txt "fix: tidy the installer"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: a new file's name is checked" [ "$r" = failed ]

# Findings give the path, the line number from the hunk header, and the line
stage_only notes.txt "line one
line two by Jane"
out=$(piidiff_err)
check "check-pii diff: a finding names its path and line" \
    grep -q "^notes.txt:2: mentions 'Jane'" <<EOF
$out
EOF
check "check-pii diff: a finding shows the line" grep -q "^    line two by Jane$" <<EOF
$out
EOF
stage_only jexample.txt "fix: tidy"
out=$(piidiff_err)
check "check-pii diff: a path finding says it is a path" \
    grep -q "^jexample.txt (path): mentions 'Example'" <<EOF
$out
EOF

# --skip-line skips git/config's name and email lines...
stage_only git/config "[user]
	name = Jane Example
	email = jane${at}example.org"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: without --skip-line, git/config's name line fails" [ "$r" = failed ]
check "check-pii diff: --skip-line skips git/config's name and email lines" \
    piidiff --skip-line "$config_skip"
check "check-pii diff: --skip-line=PATH:LINE works too" piidiff "--skip-line=$config_skip"

# ...but the rest of git/config is checked like any other file
stage_only git/config "[include]
	path = ${slash}home${slash}someone${slash}x"
if piidiff --skip-line "$config_skip"; then r=passed; else r=failed; fi
check "check-pii diff: the rest of git/config is checked" [ "$r" = failed ]

# and the path ERE matches the whole path
stage_only notes.txt "	name = Jane Example"
if piidiff --skip-line "$config_skip"; then r=passed; else r=failed; fi
check "check-pii diff: a skipped line elsewhere is checked" [ "$r" = failed ]
stage_only sub/git/config "	name = Jane Example"
if piidiff --skip-line "$config_skip"; then r=passed; else r=failed; fi
check "check-pii diff: a skip's path ERE is anchored" [ "$r" = failed ]

# an invalid skip ERE fails closed
stage_only notes.txt "fix: tidy"
if piidiff --skip-line 'notes.txt:[unclosed'; then r=passed; else r=failed; fi
check "check-pii diff: an invalid --skip-line ERE fails closed" [ "$r" = failed ]

# A decision record's decision-makers line is a built-in skip...
stage_only docs/decisions/0002-a-choice.md "---
decision-makers: Jane Example
---"
check "check-pii diff: a decision record's decision-makers line passes" piidiff

# ...which --no-default-skips turns off
if piidiff --no-default-skips; then r=passed; else r=failed; fi
check "check-pii diff: --no-default-skips checks decision-makers" [ "$r" = failed ]

# ...but the rest of the record is checked
stage_only docs/decisions/0002-a-choice.md "Jane Example decided this."
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: the rest of a decision record is checked" [ "$r" = failed ]

# and the line is checked anywhere else
stage_only notes.md "decision-makers: Jane Example"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: a decision-makers line elsewhere is checked" [ "$r" = failed ]

# A hook's repo: URL in .pre-commit-config.yaml is the other built-in skip:
# its owner's handle can contain a word of user.name...
stage_only .pre-commit-config.yaml "repos:
  - repo: https://github.com/JaneExampleson/linter"
check "check-pii diff: a hook's repo: URL passes" piidiff

# ...but a comment on that line is checked
stage_only .pre-commit-config.yaml "  - repo: https://github.com/x/linter # from Jane"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: a comment on a repo: line is checked" [ "$r" = failed ]

# and so is a repo: line anywhere else
stage_only notes.yaml "  - repo: https://github.com/JaneExampleson/linter"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: a repo: line elsewhere is checked" [ "$r" = failed ]

# The patterns file applies in staged-diff mode too
stage_only notes.txt "deploy for acme-widget"
if (cd "$prepo" && XDG_CONFIG_HOME="$tmp/local-xdg" PATH="$tmp/hoststub:$PATH" \
    USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii diff: a patterns file entry fails" [ "$r" = failed ]

# The checkout's parent directory, from `git rev-parse --show-toplevel`. The
# real one first: a scratch directory is at least two levels deep everywhere
# (verified on Windows, MSYS2's /tmp).
parent=$(dirname "$(git -C "$prepo" rev-parse --show-toplevel)")
stage_only notes.txt "built in $parent/x"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: the checkout's parent directory fails" [ "$r" = failed ]
# Then made-up ones, from a git wrapper answering only --show-toplevel
real_git=$(command -v git)
mkdir -p "$tmp/gitstub"
cat > "$tmp/gitstub/git" <<EOF
#!/bin/sh
if [ "\$1" = rev-parse ] && [ "\$2" = --show-toplevel ]; then
    echo "\$STUB_TOP"
    exit 0
fi
exec "$real_git" "\$@"
EOF
chmod +x "$tmp/gitstub/git"
pii_top() {
    printf '%s\n' "$2" > "$tmp/msg.txt"
    (cd "$prepo" && STUB_TOP=$1 XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/gitstub:$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null)
}
if pii_top /work/acme/proj "see /work/acme/other"; then r=passed; else r=failed; fi
check "check-pii parent: a POSIX parent fails" [ "$r" = failed ]
check "check-pii parent: a relative path with the same names passes" pii_top /work/acme/proj "see work/acme"
if pii_top D:/work/acme/proj 'in D:\work\acme\other'; then r=passed; else r=failed; fi
check "check-pii parent: a drive parent's backslash spelling fails" [ "$r" = failed ]
if pii_top D:/work/acme/proj "in /d/work/acme/other"; then r=passed; else r=failed; fi
check "check-pii parent: a drive parent's MSYS2 spelling fails" [ "$r" = failed ]
check "check-pii parent: a parent one level below the root is skipped" \
    pii_top /src/proj "see /src/other"
check "check-pii parent: a drive parent one level deep is skipped" \
    pii_top D:/work/proj 'see D:\work\other'

# --files: the whole content and the paths of the files given
frepo="$tmp/files-repo"
git init -q "$frepo"
git -C "$frepo" config user.name "Jane Example"
printf '%s\n' "one" "two" "three by Jane" > "$frepo/notes.txt"
printf '%s\n' "fix: tidy" > "$frepo/clean.txt"
printf '%s\n' "fix: tidy" > "$frepo/a=b.txt"
piifiles() {
    (cd "$frepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --files "$@")
}
check "check-pii files: clean files pass" piifiles clean.txt a=b.txt 2>/dev/null
out=$(piifiles clean.txt notes.txt 2>&1 >/dev/null || true)
check "check-pii files: a line fails, with its path and line" \
    grep -q "^notes.txt:3: mentions 'Jane'" <<EOF
$out
EOF
check "check-pii files: --skip-line applies" piifiles --skip-line 'notes\.txt:by Jane' notes.txt 2>/dev/null
printf '%s\n' "fix: tidy" > "$frepo/jexample.txt"
if piifiles jexample.txt 2>/dev/null; then r=passed; else r=failed; fi
check "check-pii files: a path is checked" [ "$r" = failed ]
check "check-pii files: no files passes" piifiles

# --history, and committers' names from the history, in a repo with commits
hrepo="$tmp/history-repo"
git init -q "$hrepo"
git -C "$hrepo" config user.name "Jane Example"
hcommit() { # hcommit <author> <message>: commit everything as <author>
    git -C "$hrepo" -c core.autocrlf=false add -A
    git -C "$hrepo" -c user.name="$1" -c user.email=x -c commit.gpgsign=false \
        commit -q --allow-empty -m "$2"
}
printf '%s\n' "a line by Jane" > "$hrepo/notes.txt"
hcommit "Sam Otherperson" "feat: add notes"
: > "$hrepo/jexample.txt"
hcommit "Sam Otherperson" "feat: add an empty file"
rm "$hrepo/jexample.txt"
printf '%s\n' "a clean line" > "$hrepo/notes.txt"
hcommit "Sam Otherperson" "fix: tidy"
hcommit "helper-robot[bot]" "chore: bump"
hcommit "unknown" "chore: tidy"
hcommit "Sam Otherperson" "docs: thanks to Jane"
piihist() {
    (cd "$hrepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" "$@")
}
out=$(piihist --history 2>&1 >/dev/null || true)
check "check-pii history: a removed line is found" \
    grep -q "^[0-9a-f]* notes.txt:1: mentions 'Jane'" <<EOF
$out
EOF
check "check-pii history: a commit message is found" \
    grep -q "^[0-9a-f]* commit message:1: mentions 'Jane'" <<EOF
$out
EOF
check "check-pii history: a removed file's empty path is found" \
    grep -q "^[0-9a-f]* jexample.txt (path): mentions 'Example'" <<EOF
$out
EOF
printf '%s\n' "thanks to Otherperson" > "$tmp/msg.txt"
if piihist --commit-msg "$tmp/msg.txt" 2>/dev/null; then r=passed; else r=failed; fi
check "check-pii names: a committer's name from the history fails" [ "$r" = failed ]
check "check-pii names: --no-history-names turns it off" \
    piihist --no-history-names --commit-msg "$tmp/msg.txt" 2>/dev/null
printf '%s\n' "the cause is unknown; ask the helper-robot" > "$tmp/msg.txt"
check "check-pii names: bots and one-word names are not checked" \
    piihist --commit-msg "$tmp/msg.txt" 2>/dev/null

unit_finish
