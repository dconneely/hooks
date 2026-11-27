#!/bin/sh

set -e

# shellcheck source=tests/common.sh
. "$(dirname "$0")/common.sh"
unit_init "$0"

# The pins: package.json for the manifest's hooks, and the local copies'
# additional_dependencies in .pre-commit-config.yaml, which must match
pkg_pin() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" "$repo_dir/package.json"; }
cfg_pins() { grep -o "$1@[^],]*" "$repo_dir/.pre-commit-config.yaml" | sed "s/^$1@//" | sort -u; }
is_exact_version() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }
for tool in prettier markdownlint-cli2; do
    pkg_version=$(pkg_pin "$tool")
    check "markdown: package.json pins $tool exactly ($pkg_version)" is_exact_version "$pkg_version"
    check "markdown: the local copies pin $tool at package.json's version" \
        [ "$(cfg_pins "$tool")" = "$pkg_version" ]
done

# Prettier's printWidth and markdownlint's MD013 line_length must match, or
# lint-markdown fails what format-markdown wrote
print_width=$(sed -n 's/.*"printWidth": *\([0-9]*\).*/\1/p' "$repo_dir/config/prettierrc.json")
line_length=$(sed -n 's/.*"line_length": *\([0-9]*\).*/\1/p' "$repo_dir/config/.markdownlint-cli2.jsonc")
widths_match() { [ -n "$print_width" ] && [ "$print_width" = "$line_length" ]; }
check "markdown: printWidth ($print_width) equals MD013's line_length" widths_match

long='This sentence is deliberately long so that it runs well past one hundred columns and Prettier has to wrap it.'
widest() { awk '{ if (length > m) m = length } END { print m + 0 }' "$1"; }

if manifest_init; then
    # format-markdown: wraps at 100, leaves code blocks alone, fails when it
    # changes a file, and passes a formatted one
    mkdir -p "$consumer/docs"
    printf '%s\n' '# Title' '' "$long" '' '*  one' '*  two' '' '```js' 'const x = {a:1}' '```' \
        > "$consumer/docs/messy.md"
    printf '%s\n' '# Title' '' '- one' '- two' > "$consumer/tidy.md"
    if try_hook format-markdown docs/messy.md; then r=passed; else r=failed; fi
    check "format-markdown: an unformatted file fails" [ "$r" = failed ]
    check "format-markdown: and its list is rewritten" grep -q '^- one$' "$consumer/docs/messy.md"
    check "format-markdown: and its prose is wrapped at 100 columns" \
        [ "$(widest "$consumer/docs/messy.md")" -eq 100 ]
    check "format-markdown: and its code block is left alone" \
        grep -q '^const x = {a:1}$' "$consumer/docs/messy.md"
    check "format-markdown: a formatted file passes" try_hook format-markdown tidy.md

    # The consumer's own Prettier config is ignored, and an .editorconfig's
    # indent doesn't change the output: the shipped config sets tabWidth
    printf '%s\n' '# List' '' '- one' '  - nested' '- two' > "$consumer/nested.md"
    printf '%s\n' '{ "printWidth": 40, "tabWidth": 4 }' > "$consumer/.prettierrc.json"
    printf '%s\n' 'root = true' '[*]' 'indent_style = tab' 'indent_size = 4' > "$consumer/.editorconfig"
    printf '%s\n' '# Long' '' "$long" > "$consumer/long.md"
    try_hook format-markdown nested.md long.md || true
    check "format-markdown: a consumer's .prettierrc.json is ignored" \
        [ "$(widest "$consumer/long.md")" -eq 100 ]
    check "format-markdown: a consumer's .editorconfig doesn't change list indents" \
        grep -q '^  - nested$' "$consumer/nested.md"
    rm "$consumer/.prettierrc.json" "$consumer/.editorconfig"

    # lint-markdown: the 100-column lines format-markdown wrote pass (they
    # would fail markdownlint's default of 80), and other rules still apply
    check "lint-markdown: format-markdown's output passes" \
        try_hook lint-markdown docs/messy.md tidy.md long.md
    printf '%s\n' '# Anchors' '' '## Real heading' '' 'See [the section](#missing-heading).' \
        > "$consumer/anchors.md"
    if try_hook lint-markdown anchors.md; then r=passed; else r=failed; fi
    check "lint-markdown: a broken link fragment fails (MD051)" [ "$r" = failed ]

    # A consumer's .markdownlint-cli2.jsonc holding one exception merges
    # with the shipped rules, and keeps the 100-column limit
    printf '%s' '{ "config": { "MD051": false } }' > "$consumer/.markdownlint-cli2.jsonc"
    check "lint-markdown: an exception in .markdownlint-cli2.jsonc merges" \
        try_hook lint-markdown anchors.md long.md
    rm "$consumer/.markdownlint-cli2.jsonc"
fi

unit_finish
