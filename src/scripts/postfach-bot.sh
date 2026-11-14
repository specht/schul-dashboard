#!/usr/bin/env bash
# Postfach-Bot: handles the approved mailbox jobs from the dashboard
# (password resets, new mailboxes – page "Postfach-Anfragen und
# E-Mail-Briefe") while this runs. Stop with Ctrl+C when you're done.
# Runs only on the maintainer's machines, see src/mail-account-bot/README.md.
#
#   ./src/scripts/postfach-bot.sh            background mode (serve)
#   ./src/scripts/postfach-bot.sh --show     the same, with a visible browser
set -euo pipefail
cd "$(dirname "$0")/../mail-account-bot"
if [ ! -d node_modules ] || [ package-lock.json -nt node_modules ]; then
    npm ci --no-audit --no-fund --loglevel=error
fi
echo "Postfach-Bot läuft – Aufträge kommen vom Dashboard. Beenden mit Strg+C."
exec node bot.js serve "$@"
