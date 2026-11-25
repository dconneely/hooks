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

# Optional machine-local checklist under XDG_CONFIG_HOME/dotfiles/pii-patterns
mkdir -p "$tmp/local-xdg/dotfiles"
cr=$(printf '\r')
cat > "$tmp/local-xdg/dotfiles/pii-patterns" <<EOF
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
mkdir -p "$tmp/bad-xdg/dotfiles"
printf '%s\n' 'regex: [unclosed' > "$tmp/bad-xdg/dotfiles/pii-patterns"
printf '%s\n' "fix: clean text" > "$tmp/msg.txt"
if (cd "$prepo" && XDG_CONFIG_HOME="$tmp/bad-xdg" PATH="$tmp/hoststub:$PATH" USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" --commit-msg "$tmp/msg.txt" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii local list: invalid regex fails closed" [ "$r" = failed ]

# Git's comment lines and anything below the scissors line are ignored
check "check-pii msg: comments and scissors section ignored" pii "fix: tidy
# Jane Example, jane${at}example.org
# ------------------------ >8 ------------------------
${slash}home${slash}someone"

# hooks/check-pii.sh on the staged diff (its pre-commit mode), in the same
# scratch repo.
piidiff() {
    (cd "$prepo" && XDG_CONFIG_HOME="$tmp/empty-xdg" PATH="$tmp/hoststub:$PATH" \
        USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" 2>/dev/null)
}
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

# git/config's name and email lines are the one exception...
stage_only git/config "[user]
	name = Jane Example
	email = jane${at}example.org"
check "check-pii diff: git/config's name and email lines pass" piidiff

# ...but the rest of git/config is checked like any other file
stage_only git/config "[include]
	path = ${slash}home${slash}someone${slash}x"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: the rest of git/config is checked" [ "$r" = failed ]

# and the exception is only for git/config
stage_only notes.txt "	name = Jane Example"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: a name line elsewhere is checked" [ "$r" = failed ]

# A decision record's decision-makers line is the other exception...
stage_only docs/decisions/0002-a-choice.md "---
decision-makers: Jane Example
---"
check "check-pii diff: a decision record's decision-makers line passes" piidiff

# ...but the rest of the record is checked
stage_only docs/decisions/0002-a-choice.md "Jane Example decided this."
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: the rest of a decision record is checked" [ "$r" = failed ]

# and the line is checked anywhere else
stage_only notes.md "decision-makers: Jane Example"
if piidiff; then r=passed; else r=failed; fi
check "check-pii diff: a decision-makers line elsewhere is checked" [ "$r" = failed ]

# A hook's repo: URL in .pre-commit-config.yaml is the third exception: its
# owner is a third party, whose handle can contain a word of user.name...
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

# local pii-patterns applies in staged-diff mode too
stage_only notes.txt "deploy for acme-widget"
if (cd "$prepo" && XDG_CONFIG_HOME="$tmp/local-xdg" PATH="$tmp/hoststub:$PATH" \
    USERPROFILE=/x/tester sh "$repo_dir/hooks/check-pii.sh" 2>/dev/null); then r=passed; else r=failed; fi
check "check-pii diff: local pii-patterns entry fails" [ "$r" = failed ]

unit_finish
