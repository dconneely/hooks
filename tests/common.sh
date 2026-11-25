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

unit_finish() {
    echo "----"
    echo "$pass passed, $fail failed"
    [ "$fail" -eq 0 ]
}
