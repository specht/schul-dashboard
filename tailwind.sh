#!/usr/bin/env bash
# Builds src/static/tailwind.css from the files tracked by git
# (tailwind.config.js), see doc/Development.md.
#
#   ./tailwind.sh          rebuild on every change (started by ./config.rb up in development)
#   ./tailwind.sh build    rebuild once
#   ./tailwind.sh check    is src/static/tailwind.css what the tracked files give? (./test.sh all)
set -euo pipefail
cd "$(dirname "$0")"
TAILWIND=(npx -y tailwindcss@3.0.24)

case "${1:-watch}" in
    watch) exec "${TAILWIND[@]}" -o src/static/tailwind.css --watch ;;
    build) "${TAILWIND[@]}" -o src/static/tailwind.css ;;
    check)
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        "${TAILWIND[@]}" -o "$tmp" 2>/dev/null
        if ! cmp -s src/static/tailwind.css "$tmp"; then
            echo "tailwind.css doesn't match the tracked pages: ./tailwind.sh build, then commit src/static/tailwind.css" >&2
            exit 1
        fi
        if git diff --quiet HEAD -- src/static/tailwind.css; then
            echo "tailwind.css is up to date"
        else
            echo "tailwind.css is up to date, but not committed yet – commit it with the pages that need it"
        fi
        ;;
    *) echo "usage: $0 [watch|build|check]" >&2; exit 2 ;;
esac
