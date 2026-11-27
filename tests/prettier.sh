#!/bin/sh

set -e

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
unit_init "$0"

# The manifest's prettier hook, run as a consumer runs it, and the Prettier
# version pinned in two places: package.json for the hook, and
# .pre-commit-config.yaml for this repository's local copy of it.
pkg_version=$(sed -n 's/.*"prettier": *"\([^"]*\)".*/\1/p' "$repo_dir/package.json")
cfg_version=$(sed -n 's/.*prettier@\([0-9][0-9.]*\).*/\1/p' "$repo_dir/.pre-commit-config.yaml")
is_exact_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }
check "prettier: package.json pins Prettier exactly" is_exact_version "$pkg_version"
check "prettier: .pre-commit-config.yaml's Prettier matches package.json ($pkg_version)" \
    [ "$pkg_version" = "$cfg_version" ]

if manifest_init; then
    printf '%s\n' '# Title' '' '*  one' '*  two' > "$consumer/messy.md"
    printf '%s\n' '# Title' '' '- one' '- two' > "$consumer/tidy.md"
    if try_hook prettier messy.md; then r=passed; else r=failed; fi
    check "prettier: an unformatted Markdown file fails" [ "$r" = failed ]
    check "prettier: and is rewritten" grep -q '^- one$' "$consumer/messy.md"
    check "prettier: a formatted Markdown file passes" try_hook prettier tidy.md
fi

unit_finish
