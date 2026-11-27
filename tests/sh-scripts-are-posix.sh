#!/bin/sh

set -e

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
unit_init "$0"

# The manifest's sh-scripts-are-posix hook, run as a consumer runs it
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
