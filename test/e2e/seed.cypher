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

// Teachers who get their login code by SMS and have no code app, without
// first-login grace period (otp-nudge.spec.ts): the number 015111111111,
// obfuscated with SMS_PHONE_NUMBER_PASSPHRASE of credentials.template.rb.
MATCH (u:User) WHERE u.email IN ['sms.eins@beispielschule.de', 'sms.zwei@beispielschule.de']
SET u.telephone_number = 'aNScHygDV6X5CRWT',
    u.telephone_number_changed = '2024-09-01',
    u.preferred_login_method = 'sms',
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

// A seating plan from before there were plans of one's own in a subject room
// (no lehrer): Clarke made it in 323, where he teaches 5a. It stays visible
// to him there (sitzplan-fachraum.spec.ts).
MATCH (u:User {email: 'clarke@beispielschule.de'})
MERGE (sc:SeatingCycle {id: 'e2efachraumalt'})
SET sc.klasse = '5a', sc.raum = '323', sc.mode = 'manual', sc.created_at = 1730000000,
    sc.saved_at = 1730000000, sc.seats = '{}', sc.unresolved = '[]', sc.satisfied_emails = '[]',
    sc.forced_pairs = '[]', sc.forbidden_pairs = '[]', sc.fixed_rules = '[]'
MERGE (sc)-[:STARTED_BY]->(u);

// Neues Design, lists with an archive (design-preview-polls/-news.spec.ts):
// a poll of the admin from an earlier school year, and website news of two
// earlier years (/manage_news loads them by year).
MATCH (u:User {email: 'clarke@beispielschule.de'})
MERGE (p:Poll {id: 'e2earchivpoll'})
SET p.title = 'Archiv-Umfrage Schuljahr 2023/24', p.items = '[]',
    p.created = 1696150800, p.updated = 1696150800
MERGE (p)-[:ORGANIZED_BY]->(u);

UNWIND [
  [1556704800, '2019-05-01 12:00:00', 'Archiv-Beitrag 2019 Nr. 1'],
  [1559383200, '2019-06-01 12:00:00', 'Archiv-Beitrag 2019 Nr. 2'],
  [1561975200, '2019-07-01 12:00:00', 'Archiv-Beitrag 2019 Nr. 3'],
  [1527847200, '2018-06-01 12:00:00', 'Archiv-Beitrag 2018 Nr. 1']
] AS n
MERGE (e:NewsEntry {timestamp: n[0]})
SET e.date = n[1], e.title = n[2], e.content = 'Ein Beitrag aus dem Archiv.',
    e.sticky = false, e.published = true;
