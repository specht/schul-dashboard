'use strict';
// Checks whether a mailbox accepts a password: IMAP LOGIN, then LOGOUT. Used
// before a reset (already the original password? then the control panel is
// not touched at all) and after it (proof that exactly this mailbox now has
// the new password).
const net = require('net');
const tls = require('tls');

function quote(text) {
    if (/[\r\n\0]/.test(text)) throw new Error('IMAP: unzulässige Zeichen');
    return '"' + text.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

// resolves true (login accepted), false (rejected); rejects on other errors
function imapLoginWorks({ host, port, tls: useTls = true, timeoutMs = 20000 }, user, password) {
    return new Promise((resolve, reject) => {
        // before connecting: a bad value rejects here instead of in a socket handler
        const command = `a1 LOGIN ${quote(user)} ${quote(password)}\r\n`;
        const socket = useTls
            ? tls.connect({ host, port, servername: host })
            : net.connect({ host, port });
        let buffer = '';
        let stage = 'greeting';
        let result = null;
        const finish = (err, value) => {
            clearTimeout(timer);
            socket.destroy();
            if (err) reject(err); else resolve(value);
        };
        const timer = setTimeout(() => finish(new Error('IMAP: Zeitüberschreitung')), timeoutMs);
        socket.setEncoding('utf8');
        socket.on('error', (err) => finish(new Error(`IMAP: ${err.code || err.message}`)));
        socket.on('close', () => { if (result !== null) finish(null, result); else finish(new Error('IMAP: Verbindung geschlossen')); });
        socket.on('data', (chunk) => {
            buffer += chunk;
            let idx;
            while ((idx = buffer.indexOf('\r\n')) >= 0) {
                const line = buffer.slice(0, idx);
                buffer = buffer.slice(idx + 2);
                if (stage === 'greeting') {
                    if (!/^\* OK/i.test(line)) return finish(new Error('IMAP: unerwartete Begrüßung'));
                    stage = 'login';
                    socket.write(command);
                } else if (stage === 'login' && line.startsWith('a1 ')) {
                    if (/^a1 OK/i.test(line)) result = true;
                    else if (/^a1 NO/i.test(line)) result = false;
                    else return finish(new Error('IMAP: unerwartete Antwort'));
                    stage = 'logout';
                    socket.write('a2 LOGOUT\r\n');
                } else if (stage === 'logout' && line.startsWith('a2 ')) {
                    finish(null, result);
                }
            }
        });
    });
}

module.exports = { imapLoginWorks };
