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
        // shared by every machine: run lock, pause, IONOS logins of the day
        claim: (host) => post('claim', { host }),
        release: (host) => post('release', { host }),
        pause: (host, reason) => post('pause', { host, reason: String(reason).slice(0, 500) }),
        loginAttempt: (host) => post('login_attempt', { host }),
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
