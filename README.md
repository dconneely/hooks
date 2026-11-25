# hooks

Hooks for prek and pre-commit, shared between repositories.

## check-pii

`check-pii` fails a commit whose staged diff adds personal details, and `check-pii-msg` does the
same for its message. The details are derived at commit time: each word of Git's `user.name`, the OS
username, the hostname, anything shaped like an email address, and any path into a user-home
directory. A machine-local file can add more:
`${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/pii-patterns`, one case-insensitive fixed string per
line, or `regex:` and an extended regular expression. `#` lines and blank lines are ignored.

The hooks are POSIX sh scripts, so Windows needs `sh` on `PATH`, as MSYS2 provides.

## Tests

Run `sh tests/check-pii.sh`. Each test runs the hook in a scratch repository with a made-up identity
and stubbed commands, never the machine's own.
