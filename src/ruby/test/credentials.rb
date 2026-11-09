# Credentials for the isolated test stack (env.test.rb, ./test.sh).
#
# Loaded instead of credentials.rb via DASHBOARD_CREDENTIALS. Starts from the
# template and makes sure tests never talk to a real server: every external
# host points to the reserved .invalid TLD (RFC 6761), and WEB_ROOT points to
# the test stack, not to a development instance on port 8025.

require './credentials.template.rb'

warn_level = $VERBOSE
$VERBOSE = nil

# must match NGINX_HOST_PORT in env.test.rb
WEB_ROOT = 'http://localhost:8125'

SCHUL_MAIL_LOGIN_URL = 'https://mail.test.invalid'
SCHUL_MAIL_LOGIN_SMTP_HOST = 'smtp.test.invalid'
SCHUL_MAIL_LOGIN_IMAP_HOST = 'imap.test.invalid'
SMTP_SERVER = 'smtp.test.invalid'
WEBSITE_HOST = 'dashboard.test.invalid'
VOTING_WEBSITE_URL = 'https://abstimmung.test.invalid'
TECHNIK_HILFE_WEBSITE_URL = 'https://hilfe.test.invalid'
NEXTCLOUD_URL = 'http://nextcloud.test.invalid'
NEXTCLOUD_URL_FROM_RUBY_CONTAINER = 'http://nextcloud.test.invalid'
JITSI_HOST = 'meet.test.invalid'
STREAM_SITE_URL = 'https://info.test.invalid/'
BIB_HOST = 'https://bibliothek.test.invalid'
UNTIS_VERTRETUNGSPLAN_BASE_URL = 'https://vertretungsplan.test.invalid'

# The rooms used in the example timetable (the template declares others,
# so no class would have a room and seating plans would be unavailable).
ROOM_ORDER = %w(108 129 317 323)

# All mail goes to the Mailpit container of the test stack, where the tests
# read login codes from (see test/e2e/tests/fixtures.ts).
SMTP_SERVER = 'mailpit'
SMTP_DOMAIN = 'test.invalid'
if defined? Mail
    Mail.defaults do
        delivery_method :smtp, {
            :address => SMTP_SERVER,
            :port => 587,
            :domain => SMTP_DOMAIN,
            :user_name => 'test',
            :password => 'test',
            :authentication => 'login',
            :enable_starttls_auto => false
        }
    end
end

$VERBOSE = warn_level
