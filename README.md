# hooks

Hooks for prek and pre-commit, shared between repositories. MIT licence; see `LICENCE`.

## check-pii

Fails when personal details are about to enter a repository. The details are derived at run time, so
nothing personal is committed here or in the repositories that use it:

- anything shaped like an email address;
- each word of Git's `user.name`;
- each word of the other names in the repository's history, from `git log` (authors and committers).
  Bots, one-word names, words under three letters and words with digits or punctuation other than
  `-` and `'` are not checked;
- the OS username and the hostname, except generic ones such as `root` and `localhost`;
- any path into a user-home directory, in any spelling;
- the directory holding the checkout, in each spelling (`D:/x/y`, `D:\x\y`, `/d/x/y`), unless it is
  fewer than two levels below the root or under a home directory;
- the entries in the machine-local patterns file.

| Hook                | Stage        | Checks                                                      |
| ------------------- | ------------ | ----------------------------------------------------------- |
| `check-pii`         | `pre-commit` | the staged diff's added lines and new paths                 |
| `check-pii-msg`     | `commit-msg` | the commit message                                          |
| `check-pii-files`   | `manual`     | the whole content and paths of the files                    |
| `check-pii-history` | `manual`     | every added line, new path and commit message on any branch |

Run the manual hooks after adding a pattern, since earlier content was never checked against it, and
before publishing a repository. Under MSYS2 on Windows, the history hook took 15 to 55 seconds on
repositories of 12 to 480 commits (November 2026); the time follows the size of the history's diffs
more than the number of commits.

```sh
prek run --stage manual check-pii-files --all-files
prek run --stage manual check-pii-history
```

Each finding gives a location, the check, and the line as written:

```text
notes.txt:2: mentions 'Jane' (from git user.name)
    line two by Jane
```

### The patterns file

`${XDG_CONFIG_HOME:-$HOME/.config}/check-pii/patterns`, on each machine, never committed. One entry
per line; `#` lines and blank lines are ignored:

- a plain line rejects a case-insensitive fixed string;
- `regex:` and an extended regular expression rejects what it matches, ignoring case;
- `!` and a fixed string allows it: each occurrence is removed, ignoring case, before any check
  runs, so the rest of the line is still checked. For example, a third party's handle that shares a
  word with your name.

### Options

Add these as the hook's `args`:

- `--skip-line PATH:LINE` skips a line of file content matching the extended regular expression
  `LINE`, in a file whose whole path matches `PATH`. It splits at the first `:` and can be repeated.
  For example, a dotfiles repository's own Git identity:

  ```yaml
  - id: check-pii
    args: [--skip-line, 'git/config:^[[:blank:]]*(name|email)[[:blank:]]*=']
  ```

  Two skips are built in: a `repo:` line in `.pre-commit-config.yaml` holding only an https URL
  without `@`, and a `decision-makers:` line in `docs/decisions/*.md`.

- `--no-default-skips` turns off the built-in skips.
- `--no-history-names` stops checking the names from the history.

### In CI

On a CI runner the identity and hostname are the runner's and the patterns file is missing, so few
checks mean anything there. A consumer's CI skips them:

```yaml
env:
  SKIP: check-pii,check-pii-msg
```

check-pii is a POSIX sh script, so Windows needs `sh` on `PATH`, as MSYS2 provides.

## format-markdown and lint-markdown

`format-markdown` formats Markdown with Prettier, and `lint-markdown` lints it with
markdownlint-cli2, each with the config in `config/`, so a repository needs no Markdown config of
its own:

- Prettier wraps prose at 100 columns, with 2-space indents, and leaves code blocks alone.
- markdownlint applies its default rules, with lines up to 100 columns (code blocks, tables and
  headings exempt) and the same heading allowed under different parents.

List `format-markdown` first, so `lint-markdown` checks what it wrote:

```yaml
- repo: https://github.com/dconneely/hooks
  rev: <commit> # frozen: v0.2.0
  hooks:
    - id: format-markdown
    - id: lint-markdown
```

prek installs both tools, at the versions `package.json` pins, once per machine and release, so no
commit downloads them and concurrent runs don't race to install them, as they do with `npx`. The
first run takes about 40 seconds on Windows, later runs under two.

Exceptions:

- To skip a file, use the hook's `exclude:`. Prettier also honours a `.prettierignore`.
- To change a markdownlint rule, put it alone in a `.markdownlint-cli2.jsonc`, which merges with
  these rules, at the root or in a subdirectory: `{ "config": { "MD051": false } }`. A
  `.markdownlint.jsonc` replaces them all instead, and lines fall back to 80 columns.
- A repository's `.prettierrc.json` is ignored, and so are an `.editorconfig`'s indents.

An editor doesn't see this config. For VS Code's markdownlint extension, copy the rules from
`config/.markdownlint-cli2.jsonc` into its `markdownlint.config` setting.

## sh-scripts-are-posix

Fails a `.sh` file whose shebang names Bash. ShellCheck checks a script in the dialect its shebang
names, so it would pass Bash-only syntax that `sh` then fails on. Name a Bash script `.bash`.

## Tests

- `sh tests/check-pii.sh` runs check-pii in a scratch repository with a made-up identity and stubbed
  commands, never the machine's own. CI runs it on Ubuntu, macOS and Windows. It takes under three
  minutes on Windows, where each run of the hook costs about three seconds under MSYS2, and much
  less elsewhere.
- `sh tests/markdown.sh` and `sh tests/sh-scripts-are-posix.sh` run those hooks from the manifest
  through `prek try-repo`, as a consumer does, from a scratch clone of the working tree. The first
  also checks that the tool versions in `package.json` and in `.pre-commit-config.yaml`'s local
  copies match, and that Prettier's width equals markdownlint's line length. CI runs them on Ubuntu.
  The first takes about a minute the first time, while prek installs the tools.
