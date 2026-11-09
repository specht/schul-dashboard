// Prepares accounts of the test stack for the login tests (run by ./test.sh
// after startup). Users already exist – main.rb creates them from
// src/example-data. The OTP secret must match TEST_OTP_SECRET in
// tests/fixtures.ts. Test stack only, example data only.

// Teacher with forced two-factor login: no first-login grace period,
// second factor via OTP app.
MATCH (u:User {email: 'torstenson@beispielschule.de'})
SET u.otp_token = 'JBSWY3DPEHPK3PXP',
    u.last_access = '2024-09-01',
    u.force_2fa_exception_deadline = 0;

// Someone who still has the "Technikamt" role in the database but is no
// longer in the school's data (e.g. left the school) – this happens in
// real data and must not break the admin pages.
MERGE (u:User {email: 'ehemalig.technikamt@mail.beispielschule.de'})
MERGE (v:Techpost)
MERGE (u)-[:HAS_AMT {amt: 'technikamt'}]->(v);

// Teacher/admin who logs in with the OTP app as first factor (and is still
// in the first-login grace period, so no second factor).
MATCH (u:User {email: 'clarke@beispielschule.de'})
SET u.otp_token = 'JBSWY3DPEHPK3PXP',
    u.preferred_login_method = 'otp';

// A tablet set booking for the Silentium monitor (monitor.spec.ts). Seeded
// for yesterday, today and tomorrow so that exactly one of them is "today"
// for the dashboard, whatever the time zone difference of date() is.
MATCH (t:TabletSet {id: 'Tabletsatz 1'}), (u:User {email: 'torstenson@beispielschule.de'})
UNWIND [-1, 0, 1] AS offset
WITH t, u, toString(date() + duration({days: offset})) AS datum
MERGE (b:Booking {datum: datum, start_time: '09:00', end_time: '10:30', reason: 'E2E-Buchung'})
MERGE (b)-[:BOOKED]->(t)
MERGE (b)-[:BOOKED_BY]->(u);
