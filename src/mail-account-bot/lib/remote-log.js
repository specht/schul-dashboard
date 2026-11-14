'use strict';
// The bot's log lines also go to the dashboard, so the admin sees on
// /postfaecher what the bot is doing. Batched, in order; if the dashboard
// can't be reached, the lines wait (at most `maxQueue`) and are tried again
// later – the local log file always has them all. Never blocks the work.
class RemoteLog {
    constructor(send, { delayMs = 300, maxQueue = 500, batch = 100 } = {}) {
        this.send = send;
        this.delayMs = delayMs;
        this.maxQueue = maxQueue;
        this.batch = batch;
        this.queue = [];
        this.timer = null;
        this.sending = null;
        this.failures = 0;
    }

    push(text, ts = Date.now() / 1000) {
        this.queue.push({ ts, text: String(text).slice(0, 500) });
        if (this.queue.length > this.maxQueue) this.queue.splice(0, this.queue.length - this.maxQueue);
        this.schedule(this.delayMs);
    }

    schedule(delay) {
        if (this.timer || this.sending) return;
        this.timer = setTimeout(() => { this.timer = null; this.flush(); }, delay);
        if (this.timer.unref) this.timer.unref();
    }

    flush() {
        if (this.sending || this.queue.length === 0) return this.sending || Promise.resolve();
        const lines = this.queue.splice(0, this.batch);
        this.sending = Promise.resolve()
            .then(() => this.send(lines))
            .then(() => { this.failures = 0; }, () => {
                this.queue.unshift(...lines);
                if (this.queue.length > this.maxQueue) this.queue.splice(0, this.queue.length - this.maxQueue);
                this.failures += 1;
            })
            .finally(() => {
                this.sending = null;
                if (this.queue.length > 0) this.schedule(this.failures ? Math.min(60000, 5000 * this.failures) : 0);
            });
        return this.sending;
    }

    // before the process ends: what is left, for at most timeoutMs
    async close(timeoutMs = 3000) {
        const end = Date.now() + timeoutMs;
        const left = () => Math.max(1, end - Date.now());
        const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        while ((this.queue.length > 0 || this.sending) && Date.now() < end) {
            clearTimeout(this.timer);
            this.timer = null;
            const before = this.failures;
            await Promise.race([this.flush(), wait(left())]);
            if (this.failures > before) await wait(Math.min(500, left()));
        }
        clearTimeout(this.timer);
        this.timer = null;
    }
}

module.exports = { RemoteLog };
