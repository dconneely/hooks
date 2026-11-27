#!/bin/sh

set -e

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
unit_init "$0"

# The manifest's sh-scripts-are-posix hook, and .pre-commit-config.yaml's
# local copy of it, which runs on this repository: their entry and files
# patterns must match
hook_def() {
    awk '/id: sh-scripts-are-posix$/ { on = 1; next }
        on && /id:/ { exit }
        on && /^ *(entry|files):/ { sub(/^ */, ""); print }' "$1"
}
hook_def "$repo_dir/.pre-commit-hooks.yaml" > "$tmp/manifest-def"
hook_def "$repo_dir/.pre-commit-config.yaml" > "$tmp/config-def"
defs_match() { [ -s "$tmp/manifest-def" ] && cmp -s "$tmp/manifest-def" "$tmp/config-def"; }
check "sh-scripts-are-posix: .pre-commit-config.yaml's copy matches the manifest" defs_match

# The manifest's hook, run as a consumer runs it
if manifest_init; then
    printf '%s\n' '#!/bin/bash' 'echo x' > "$consumer/bash.sh"
    printf '%s\n' '#!/bin/sh' 'echo x' > "$consumer/posix.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo x' > "$consumer/script.bash"
    if try_hook sh-scripts-are-posix bash.sh; then r=passed; else r=failed; fi
    check "sh-scripts-are-posix: a .sh file with a Bash shebang fails" [ "$r" = failed ]
    check "sh-scripts-are-posix: a .sh file with an sh shebang passes" \
        try_hook sh-scripts-are-posix posix.sh
    check "sh-scripts-are-posix: a .bash file is not checked" \
        try_hook sh-scripts-are-posix script.bash
fi

unit_finish
