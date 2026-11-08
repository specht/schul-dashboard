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

// Teacher/admin who logs in with the OTP app as first factor (and is still
// in the first-login grace period, so no second factor).
MATCH (u:User {email: 'clarke@beispielschule.de'})
SET u.otp_token = 'JBSWY3DPEHPK3PXP',
    u.preferred_login_method = 'otp';
