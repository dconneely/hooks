# Shared assertions and setup for the test suites under tests/. Each suite
# sources this, calls unit_init "$0", runs its checks, then unit_finish.

unit_init() {
    # shellcheck disable=SC2034 # Used by the calling suite.
    repo_dir=$(cd "$(dirname "$1")/.." && pwd)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' 0
    # Run as a hook, the suites inherit Git's variables for this repository,
    # which would point the scratch repositories' Git commands back at it
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
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

# manifest_init: for running the manifest's hooks as a consumer does. A
# consumer pins a commit, so the working tree's manifest, package.json and
# the files the hooks run are committed to a scratch clone ($hooks_copy).
# The consumer ($consumer) is a scratch repository whose config pins that
# commit, so prek installs each hook's environment once for the suite.
# `prek try-repo` would install it afresh on every call: 7 calls took 3
# minutes on Windows. Returns 1 without prek, after saying so.
manifest_init() {
    if ! command -v prek >/dev/null 2>&1; then
        echo "skip - prek is not installed, so the manifest's hooks are not run"
        return 1
    fi
    hooks_copy="$tmp/hooks"
    git clone -q "$repo_dir" "$hooks_copy"
    cp "$repo_dir/.pre-commit-hooks.yaml" "$repo_dir/package.json" "$hooks_copy/"
    for dir in hooks bin lib config; do
        rm -rf "${hooks_copy:?}/$dir"
        cp -R "$repo_dir/$dir" "$hooks_copy/$dir"
    done
    git -C "$hooks_copy" add -A
    git -C "$hooks_copy" -c user.name=Test -c user.email=test -c commit.gpgsign=false \
        commit -q --allow-empty -m "test: working tree"
    consumer="$tmp/consumer"
    git init -q "$consumer"
    {
        printf '%s\n' 'repos:' "  - repo: '$hooks_copy'" "    rev: $(git -C "$hooks_copy" rev-parse HEAD)"
        printf '%s\n' '    hooks:'
        sed -n 's/^- id: \(.*\)$/      - id: \1/p' "$hooks_copy/.pre-commit-hooks.yaml"
    } > "$consumer/.pre-commit-config.yaml"
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
        prek run "$hook" --files "$@" >> "$tmp/prek.log" 2>&1)
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
