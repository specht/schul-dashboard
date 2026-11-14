#!/bin/sh
# Reads the IONOS 2FA QR code from a photo and stores it as totp_secret in
# the bot's configuration – without ever printing the secret. Shows the
# current code once, to compare with the authenticator app.
#
#   ./totp-from-qr.sh <photo>        (needs zbarimg: sudo apt install zbar-tools)
#
# Afterwards delete the photo – also from the phone's cloud sync and its
# "recently deleted" album.
set -eu
[ $# -eq 1 ] || { echo "Aufruf: $0 <Foto>"; exit 1; }
command -v zbarimg >/dev/null || { echo "zbarimg fehlt: sudo apt install zbar-tools"; exit 1; }
dir="$HOME/.ssh/gyst-mail-password-bot"
file="$dir/config.json"
umask 077
mkdir -p "$dir"
chmod 700 "$dir"
[ -f "$file" ] || echo '{}' > "$file"
chmod 600 "$file"
uri=$(zbarimg --raw -q "$1" 2>/dev/null | head -n 1) || true
case "$uri" in
    otpauth://totp/*) ;;
    "") echo "Kein QR-Code erkannt – Foto schärfer oder näher aufnehmen."; exit 1 ;;
    *) echo "Der QR-Code ist kein TOTP-Code (otpauth://totp/…)."; exit 1 ;;
esac
cd "$(dirname "$0")"
TOTP_URI="$uri" CONFIG_FILE="$file" node -e '
const fs = require("fs");
const os = require("os");
const { parseTotpSecret, totpAt } = require("./lib/totp");
const cfg = parseTotpSecret(process.env.TOTP_URI);
const file = process.env.CONFIG_FILE;
const config = JSON.parse(fs.readFileSync(file, "utf8"));
config.totp_secret = process.env.TOTP_URI;
if (!config.host) config.host = os.hostname();
fs.writeFileSync(file + ".tmp", JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
fs.renameSync(file + ".tmp", file);
const t = totpAt(cfg);
console.log(`Eingetragen in ${file} (Rechner: ${config.host}).`);
console.log(`Code jetzt: ${t.code} (noch ${t.remaining} s) – zeigt die Authenticator-App denselben?`);
'
