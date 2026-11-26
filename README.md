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
before publishing a repository:

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

`${XDG_CONFIG_HOME:-$HOME/.config}/check-pii/patterns`, on each machine, never committed. The older
`dotfiles/pii-patterns` in the same directory is read too. One entry per line; `#` lines and blank
lines are ignored:

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

This repository is private, so a CI runner can't clone it. prek clones a hook repository only when
some hook from it is not skipped, so a consumer's CI sets:

```yaml
env:
  SKIP: check-pii,check-pii-msg
```

The hooks are POSIX sh scripts, so Windows needs `sh` on `PATH`, as MSYS2 provides.

## Tests

Run `sh tests/check-pii.sh`. CI runs them on Ubuntu on every push, and on macOS and Windows too when
started by hand with `gh workflow run CI`. Each test runs the hook in a scratch repository with a
made-up identity and stubbed commands, never the machine's own. The suite takes under three minutes
on Windows, where each run of the hook costs about three seconds under MSYS2, and much less
elsewhere.
