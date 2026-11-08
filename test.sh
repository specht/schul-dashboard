#!/usr/bin/env bash
# Tests in containers, isolated from any development instance.
# See doc/Tests.md.
#
#   ./test.sh unit         Ruby unit tests (no database needed)
#   ./test.sh e2e          start test stack, run Playwright, stop stack
#   ./test.sh e2e-run      run Playwright against an already running stack (./test.sh up)
#   ./test.sh all          unit + e2e
#   ./test.sh up | down    start / stop (and wipe) the test stack
#   ./test.sh logs [svc]   follow logs of the test stack
#
# Environment:
#   KEEP=1                 leave the test stack running after e2e
#   E2E_ARGS="…"           extra arguments for `playwright test`
#   UPDATE_KNOWN_PAGE_ERRORS=1  rewrite test/e2e/tests/known-page-errors.json

set -euo pipefail
cd "$(dirname "$0")"

export DASHBOARD_ENV=env.test.rb
BASE_URL=http://localhost:8125
PLAYWRIGHT_IMAGE=mcr.microsoft.com/playwright:v1.55.1-noble
STACK_SERVICES=(nginx ruby neo4j timetable)

compose() { ./config.rb "$@"; }

prepare() {
    # The nginx image COPYs docker/nginx/default.conf, which only exists after
    # the normal ./config.rb ran once. The test stack mounts its own config
    # over it, so any file will do for the build.
    if [ ! -f docker/nginx/default.conf ]; then
        compose config --quiet >/dev/null
        cp docker/nginx/default.test.conf docker/nginx/default.conf
    fi
    compose build "${STACK_SERVICES[@]}"
}

wait_for() {
    local what=$1 cmd=$2 timeout=${3:-300} waited=0
    printf 'Waiting for %s ' "$what"
    until eval "$cmd" >/dev/null 2>&1; do
        sleep 2; waited=$((waited + 2)); printf '.'
        if [ "$waited" -ge "$timeout" ]; then
            echo " timed out after ${timeout}s"; return 1
        fi
    done
    echo " ok (${waited}s)"
}

ensure_sso_keys() {
    # Logged-in pages need /internal/sso-keys – throwaway keys for tests only.
    compose run --rm --no-deps -T --entrypoint "ruby test/create_sso_keys.rb" ruby
    [ -f .test-stack/internal/sso-keys/sso_private.pem ] || { echo "SSO keys missing"; return 1; }
}

stack_up() {
    stack_down
    prepare
    ensure_sso_keys
    compose up -d "${STACK_SERVICES[@]}"
    wait_for "dashboard" "curl -fsS $BASE_URL/api/ping"
    wait_for "timetable service" "compose exec -T ruby curl -fsS http://timetable:8080/api/update/all"
}

stack_down() {
    compose down --remove-orphans >/dev/null 2>&1 || true
    if [ -d .test-stack ]; then
        rm -rf .test-stack
    fi
}

run_unit() {
    compose build ruby
    compose run --rm --no-deps -T --entrypoint "ruby test/run_unit.rb" ruby
}

run_playwright() {
    docker run --rm --network host --ipc host \
        --user "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
        -e BASE_URL="$BASE_URL" -e CI=1 \
        -e STATIC_DIR=/static -e UPDATE_KNOWN_PAGE_ERRORS="${UPDATE_KNOWN_PAGE_ERRORS:-0}" \
        -v "$PWD/test/e2e:/e2e" -v "$PWD/src/static:/static:ro" -w /e2e \
        "$PLAYWRIGHT_IMAGE" \
        bash -c "npm ci --no-audit --no-fund --loglevel=error && npx playwright test ${E2E_ARGS:-}"
}

run_e2e() {
    stack_up
    local status=0
    run_playwright || status=$?
    if [ "${KEEP:-0}" = "1" ]; then
        echo "Test stack still running on $BASE_URL (./test.sh down to stop)"
    else
        stack_down
    fi
    return $status
}

case "${1:-}" in
    unit) run_unit ;;
    e2e)  run_e2e ;;
    e2e-run) run_playwright ;;
    all)  run_unit && run_e2e ;;
    up)   stack_up; echo "Test stack running on $BASE_URL" ;;
    down) stack_down ;;
    logs) shift; compose logs -f "$@" ;;
    *)    sed -n '2,15p' "$0"; exit 1 ;;
esac
