# Changelog

Changes to the hooks, by release. Versions follow [Semantic Versioning](https://semver.org/); before
1.0.0, a minor release can remove or change a hook.

## 0.2.0 - 2026-11-27

### Added

- `format-markdown`: Prettier, with this repository's config: prose wrapped at 100 columns, 2-space
  indents, code blocks left alone.
- `lint-markdown`: markdownlint-cli2, with this repository's rules: the defaults, lines up to 100
  columns, the same heading allowed under different parents. A repository's own
  `.markdownlint-cli2.jsonc` merges with them.

### Removed

- `prettier`. Replace it with `format-markdown`, replace a markdownlint-cli2 hook with
  `lint-markdown`, and delete `.prettierrc.json` and `.markdownlint-cli2.jsonc`, keeping in the
  latter only rules that differ from this repository's.

## 0.1.0 - 2026-11-27

First release.

### Added

- `check-pii`, `check-pii-msg`, `check-pii-files` and `check-pii-history`: personal details in the
  staged diff, the commit message, whole files, and the history. The details come from Git's
  `user.name`, the names in the history, the OS username, the hostname, email-shaped text, home and
  checkout paths, and `~/.config/check-pii/patterns`. Options: `--skip-line`, `--no-default-skips`
  and `--no-history-names`.
- `prettier`: Prettier 3.9.6, with the repository's own config.
- `sh-scripts-are-posix`: a `.sh` file must not declare Bash.
