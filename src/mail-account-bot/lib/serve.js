'use strict';
// Background mode: a websocket to the dashboard (outgoing, with the bot
// token) that only ever carries a wake-up call – the cases are then fetched
// and checked as always. Besides, one run every fallback_poll_minutes, in
// case the connection died silently. Reconnects with growing pauses (every
// deploy restarts the dashboard).
const WebSocket = require('ws');

function serve({ config, runOnce, log, stopSignal = null }) {
    let wake = null;
    let wakeRequested = true;
    let stopped = false;
    let ws = null;
    const wakeUp = () => { wakeRequested = true; if (wake) wake(); };
    let backoff = 5;
    const connect = () => {
        if (stopped) return;
        const url = `${config.dashboard_url.replace(/^http/, 'ws')}/ws_mail_account_bot?host=${encodeURIComponent(config.host)}`;
        ws = new WebSocket(url, { headers: { Authorization: `Bearer ${config.dashboard_token}` } });
        ws.on('open', () => { backoff = 5; log('Mit dem Dashboard verbunden'); });
        ws.on('message', (data) => {
            let message = null;
            try { message = JSON.parse(String(data)); } catch (err) { return; }
            if (message && message.command === 'wake') wakeUp();
        });
        ws.on('close', () => {
            if (stopped) return;
            log(`Verbindung zum Dashboard getrennt, neuer Versuch in ${backoff} s`);
            setTimeout(connect, backoff * 1000);
            backoff = Math.min(backoff * 2, 300);
        });
        ws.on('error', () => {});
    };
    connect();
    const loop = (async () => {
        while (!stopped) {
            if (!wakeRequested) {
                await new Promise((resolve) => {
                    wake = resolve;
                    setTimeout(resolve, config.fallback_poll_minutes * 60 * 1000);
                });
                wake = null;
            }
            if (stopped) break;
            wakeRequested = false;
            try {
                const summary = await runOnce();
                if (summary && summary.status === 'stopped') log('Angehalten – weiter erst nach der Freigabe im Dashboard');
            } catch (err) {
                log(`Fehler: ${err.message}`);
                await new Promise((resolve) => setTimeout(resolve, 60 * 1000));
            }
        }
    })();
    // for tests: stop() ends the loop and closes the connection
    return {
        loop,
        connected: () => ws && ws.readyState === WebSocket.OPEN,
        stop() { stopped = true; if (wake) wake(); if (ws) ws.close(); },
    };
}

module.exports = { serve };
