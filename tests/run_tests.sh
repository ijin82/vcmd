#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${ROOT}/tests/vcmd-tests"
BASE="${VCMD_TEST_TMPDIR:-/tmp}"

if [[ ! -x "${BIN}" ]]; then
    echo "Test binary not found: ${BIN}" >&2
    echo "Run 'make test' or 'make tests/vcmd-tests' first." >&2
    exit 2
fi

if [[ $# -gt 0 && "$1" == "--list" ]]; then
    exec "${BIN}" --list
fi

run_one() {
    local name="$1"
    local work
    work="$(mktemp -d "${BASE}/vcmd-test.XXXXXX")" || return 2
    mkdir -p "${work}/config" "${work}/cache" "${work}/data" "${work}/tmp" "${work}/runtime"
    local output
    local code
    output="$(
        cd "${ROOT}" && \
        TMPDIR="${work}/tmp" \
        XDG_CONFIG_HOME="${work}/config" \
        XDG_CACHE_HOME="${work}/cache" \
        XDG_DATA_HOME="${work}/data" \
        XDG_RUNTIME_DIR="${work}/runtime" \
        "${BIN}" --run "${name}" 2>&1
    )"
    code=$?
    printf '%s\n' "${output}"
    rm -rf -- "${work}"
    return "${code}"
}

if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--help" ]]; then
        echo "Usage: $0 [--list | TEST_NAME]"
        echo "Without arguments, runs every test in an isolated environment."
        exit 0
    fi
    run_one "$1"
    exit $?
fi

mapfile -t tests < <("${BIN}" --list)
passed=0
failed=0
skipped=0
declare -a failures=()

for line in "${tests[@]}"; do
    [[ -z "${line}" ]] && continue
    name="${line%%|*}"
    output="$(run_one "${name}")"
    code=$?
    printf '%s\n' "${output}"
    if [[ "${output}" == SKIP* ]]; then
        skipped=$((skipped + 1))
    elif [[ ${code} -eq 0 ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failures+=("${name}")
    fi
done

echo ""
echo "Summary: ${passed} passed, ${failed} failed, ${skipped} skipped"
if [[ ${failed} -gt 0 ]]; then
    printf 'Failed: %s\n' "${failures[*]}"
    exit 1
fi
exit 0
