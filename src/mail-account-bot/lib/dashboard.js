'use strict';
// The dashboard's bot interface (src/ruby/include/mail_password_reset.rb):
// approved cases only, results back. The bot never sees open cases.
function dashboardClient({ url, token, fetchImpl = fetch }) {
    const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
    const post = async (what, body) => {
        const response = await fetchImpl(`${url}/api/mail_account_bot/${what}`, { method: 'POST', headers, body: JSON.stringify(body) });
        if (response.status !== 200) throw new Error(`Dashboard antwortet mit ${response.status}`);
        return response.json();
    };
    return {
        // {cases, paused}: no cases while the bot is paused
        async pending() {
            const response = await fetchImpl(`${url}/api/mail_account_bot/pending`, { headers });
            if (response.status !== 200) throw new Error(`Dashboard antwortet mit ${response.status}`);
            const data = await response.json();
            if (!Array.isArray(data.cases)) throw new Error('Dashboard: unerwartete Antwort');
            return { cases: data.cases, paused: data.paused || null };
        },
        // shared by every machine: run lock, pause, IONOS logins of the day (counted)
        // activity: 'working' | 'waiting' (logged in, waiting until waitingUntil)
        claim: (host, activity = 'working', waitingUntil = null) =>
            post('claim', waitingUntil ? { host, activity, waiting_until: waitingUntil } : { host, activity }),
        release: (host) => post('release', { host }),
        pause: (host, reason) => post('pause', { host, reason: String(reason).slice(0, 500) }),
        loginAttempt: (host) => post('login_attempt', { host }),
        // log lines for the admin's page: [{ts, text}]
        log: (host, lines) => post('log', { host, lines }),
        // creating mailboxes: {create: [{id, mailbox, kind, password}], address_list: {ts, wanted}, paused}
        async creation() {
            const response = await fetchImpl(`${url}/api/mail_account_bot/creation`, { headers });
            if (response.status !== 200) throw new Error(`Dashboard antwortet mit ${response.status}`);
            const data = await response.json();
            if (!Array.isArray(data.create)) throw new Error('Dashboard: unerwartete Antwort');
            return data;
        },
        uploadAddressList: (rows) => post('address_list', { addresses: rows.map((r) => r.address), types: rows.map((r) => r.type) }),
        createResult: (id, ok, message) => post('create_result', { id, ok, message: String(message).slice(0, 500) }),
        async report(id, ok, message) {
            const response = await fetchImpl(`${url}/api/mail_account_bot/result`, {
                method: 'POST', headers, body: JSON.stringify({ id, ok, message: String(message).slice(0, 500) }),
            });
            if (response.status !== 200) throw new Error(`Dashboard antwortet mit ${response.status}`);
            return (await response.json()).result;
        },
    };
}

module.exports = { dashboardClient };
