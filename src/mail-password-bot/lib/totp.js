'use strict';
// TOTP (RFC 6238) for the second factor of the IONOS login. The secret is
// either the base32 text IONOS shows next to the QR code or the otpauth://
// URI from the QR code itself.
const crypto = require('crypto');

function base32Decode(text) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    const clean = text.toUpperCase().replace(/[\s=-]/g, '');
    if (!/^[A-Z2-7]+$/.test(clean)) throw new Error('TOTP-Geheimnis ist kein Base32-Text');
    let bits = 0, value = 0;
    const out = [];
    for (const ch of clean) {
        value = (value << 5) | alphabet.indexOf(ch);
        bits += 5;
        if (bits >= 8) {
            out.push((value >>> (bits - 8)) & 0xff);
            bits -= 8;
        }
    }
    return Buffer.from(out);
}

function parseTotpSecret(secret) {
    if (typeof secret !== 'string' || secret.trim() === '') throw new Error('TOTP-Geheimnis fehlt');
    let cfg = { base32: secret.trim(), digits: 6, period: 30, algorithm: 'sha1' };
    if (/^otpauth:\/\//i.test(cfg.base32)) {
        const uri = new URL(cfg.base32);
        if (uri.host !== 'totp') throw new Error('otpauth-URI ist kein TOTP');
        cfg = {
            base32: uri.searchParams.get('secret') || '',
            digits: parseInt(uri.searchParams.get('digits') || '6', 10),
            period: parseInt(uri.searchParams.get('period') || '30', 10),
            algorithm: (uri.searchParams.get('algorithm') || 'SHA1').toLowerCase(),
        };
    }
    if (![6, 7, 8].includes(cfg.digits)) throw new Error('TOTP: ungewöhnliche Stellenzahl');
    if (!(cfg.period >= 15 && cfg.period <= 120)) throw new Error('TOTP: ungewöhnliche Periode');
    if (!['sha1', 'sha256', 'sha512'].includes(cfg.algorithm)) throw new Error('TOTP: unbekannter Algorithmus');
    cfg.key = base32Decode(cfg.base32);
    if (cfg.key.length < 10) throw new Error('TOTP-Geheimnis ist zu kurz');
    delete cfg.base32;
    return cfg;
}

function hotp(cfg, counter) {
    const buf = Buffer.alloc(8);
    buf.writeBigUInt64BE(BigInt(counter));
    const hmac = crypto.createHmac(cfg.algorithm, cfg.key).update(buf).digest();
    const offset = hmac[hmac.length - 1] & 0x0f;
    const number = (hmac.readUInt32BE(offset) & 0x7fffffff) % 10 ** cfg.digits;
    return String(number).padStart(cfg.digits, '0');
}

// code, counter (time step) and seconds left in this time step
function totpAt(cfg, ms = Date.now()) {
    const seconds = Math.floor(ms / 1000);
    const counter = Math.floor(seconds / cfg.period);
    return { code: hotp(cfg, counter), counter, remaining: cfg.period - (seconds % cfg.period) };
}

module.exports = { base32Decode, parseTotpSecret, hotp, totpAt };
