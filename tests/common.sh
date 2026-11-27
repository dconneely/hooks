# Shared assertions and setup for the test suites under tests/. Each suite
# sources this, calls unit_init "$0", runs its checks, then unit_finish.

unit_init() {
    # shellcheck disable=SC2034 # Used by the calling suite.
    repo_dir=$(cd "$(dirname "$1")/.." && pwd)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' 0
    pass=0
    fail=0
}

# Pass one command; a compound condition needs a helper function.
check() {
    desc="$1"
    shift
    if "$@"; then
        pass=$((pass + 1))
        echo "ok - $desc"
    else
        fail=$((fail + 1))
        echo "FAIL - $desc"
    fi
}

# manifest_init: for running the manifest's hooks as a consumer does, with
# `prek try-repo`. try-repo takes a commit, so the working tree's manifest,
# package.json and hooks are committed to a scratch clone ($hooks_copy). The
# consumer is an empty scratch repository ($consumer). Returns 1 without
# prek, after saying so.
manifest_init() {
    if ! command -v prek >/dev/null 2>&1; then
        echo "skip - prek is not installed, so the manifest's hooks are not run"
        return 1
    fi
    hooks_copy="$tmp/hooks"
    git clone -q "$repo_dir" "$hooks_copy"
    cp "$repo_dir/.pre-commit-hooks.yaml" "$repo_dir/package.json" "$hooks_copy/"
    cp "$repo_dir"/hooks/*.sh "$hooks_copy/hooks/"
    git -C "$hooks_copy" add -A
    git -C "$hooks_copy" -c user.name=Test -c user.email=test -c commit.gpgsign=false \
        commit -q --allow-empty -m "test: working tree"
    consumer="$tmp/consumer"
    git init -q "$consumer"
}

# try_hook <hook> <file>...: runs one of the manifest's hooks on the
# consumer's files. Its output goes to $tmp/prek.log, which unit_finish
# prints if any check failed, since an expected failure and an error in
# prek itself (a failed install) look the same from the exit status.
try_hook() {
    hook=$1
    shift
    printf '%s\n' "==== try_hook $hook $*" >> "$tmp/prek.log"
    (cd "$consumer" && git -c core.autocrlf=false add -A &&
        prek try-repo "$hooks_copy" "$hook" --files "$@" >> "$tmp/prek.log" 2>&1)
}

unit_finish() {
    if [ "$fail" -ne 0 ] && [ -s "$tmp/prek.log" ]; then
        echo "---- prek output"
        cat "$tmp/prek.log"
    fi
    echo "----"
    echo "$pass passed, $fail failed"
    [ "$fail" -eq 0 ]
}
