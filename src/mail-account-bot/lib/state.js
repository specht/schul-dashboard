'use strict';
// Local state of the bot on this machine: the browser profile (keeps the
// IONOS session), screenshots, logs and the few counters below. Mode 700.
const fs = require('fs');
const path = require('path');

function today(now) {
    const d = now();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

class State {
    constructor(dir, { now = () => new Date() } = {}) {
        this.dir = dir;
        this.now = now;
        fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
        fs.chmodSync(dir, 0o700);
        for (const sub of ['profile', 'screenshots', 'recordings', 'logs']) {
            fs.mkdirSync(path.join(dir, sub), { recursive: true, mode: 0o700 });
        }
        this.profileDir = path.join(dir, 'profile');
        this.screenshotsDir = path.join(dir, 'screenshots');
        this.recordingsDir = path.join(dir, 'recordings');
        this.logFile = path.join(dir, 'logs', `${today(now)}.log`);
    }

    file(name) { return path.join(this.dir, name); }

    read(name, fallback) {
        try { return JSON.parse(fs.readFileSync(this.file(name), 'utf8')); } catch (err) { return fallback; }
    }

    write(name, value) {
        const tmp = this.file(`${name}.tmp`);
        fs.writeFileSync(tmp, JSON.stringify(value, null, 2), { mode: 0o600 });
        fs.renameSync(tmp, this.file(name));
    }

    // The pause, the run lock across machines and the logins of all machines
    // live on the dashboard. Here: this machine's own logins today (a second
    // limit), the last TOTP time step, a lock against a second instance on
    // this machine, the last stop (for the screenshot).
    lastStop() { return this.read('last-stop.json', null); }
    recordStop(reason, details = {}) { this.write('last-stop.json', { ts: this.now().toISOString(), reason, ...details }); }

    counters() {
        const c = this.read('counters.json', null);
        return c && c.date === today(this.now) ? c : { date: today(this.now), logins: 0, resets: 0 };
    }

    loginsLeft(max) { return Math.max(0, max - this.counters().logins); }

    count(what) {
        const c = this.counters();
        c[what] += 1;
        this.write('counters.json', c);
    }

    // ---- TOTP: never use a time step twice
    get lastTotpCounter() { return this.read('totp.json', { counter: 0 }).counter; }
    set lastTotpCounter(counter) { this.write('totp.json', { counter }); }

    // ---- one instance at a time
    lock() {
        const file = this.file('lock');
        try {
            fs.writeFileSync(file, String(process.pid), { flag: 'wx', mode: 0o600 });
        } catch (err) {
            const pid = parseInt(fs.readFileSync(file, 'utf8'), 10);
            let alive = false;
            try { process.kill(pid, 0); alive = true; } catch (e) { alive = e.code === 'EPERM'; }
            if (alive && pid !== process.pid) throw new Error(`Der Bot läuft schon (PID ${pid})`);
            fs.writeFileSync(file, String(process.pid), { mode: 0o600 });
        }
    }

    unlock() { fs.rmSync(this.file('lock'), { force: true }); }

    log(message) {
        const line = `${this.now().toISOString()} ${message}\n`;
        fs.appendFileSync(this.logFile, line, { mode: 0o600 });
    }
}

module.exports = { State };
