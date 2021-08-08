# -------------------------------------------------------------------
# Diese Datei bitte unter credentials.rb speichern und Werte anpassen
# (bitte keine Credentials in Git committen)
# -------------------------------------------------------------------

DEVELOPMENT = ENV['DEVELOPMENT']

# Name der Schule
SCHUL_NAME = "Beispielschule"
# 'an der' oder 'am'
SCHUL_NAME_AN_DATIV = "an der"
# Schul-Icon
SCHUL_ICON = "brand.png"

# E-Mail-Adresse der Schulleitung für das Impressum
SCHULLEITUNG_EMAIL = 'schulleitung@beispielschule.de'

# Mail-Domain für SuS-Adressen
SCHUL_MAIL_DOMAIN = "mail.beispielschule.de"

# Webmail-Login-Seite, SMTP- und IMAP-Host (nur wichtig für E-Mail-Briefe)
SCHUL_MAIL_LOGIN_URL = "https://mail.beispielmailhoster.de"
SCHUL_MAIL_LOGIN_SMTP_HOST = "smtp.beispielmailhoster.de"
SCHUL_MAIL_LOGIN_IMAP_HOST = "imap.beispielmailhoster.de"

# Bei Bedarf können alle Namen durch falsche Namen ersetzt werden
# (für Demozwecke)
USE_MOCK_NAMES = false
# Hier können E-Mail-Adressen von Lehrern angegeben werden, die nicht
# pseudonymisiert werden sollen
EXCLUDE_FROM_MOCKIFICATION = []

# Konfiguration des E-Mail-Kontos, über das E-Mails versendet werden können,
# z. B. für die Anmeldung

# SMTP Hostname
SMTP_SERVER = 'smtp.example.com'
# IMAP Hostname
IMAP_SERVER = 'imap.example.com'
SMTP_USER = 'dashboard@beispielschule.de'
SMTP_PASSWORD = '1234_nein_wirklich'
SMTP_DOMAIN = 'beispielschule.de'
SMTP_FROM = 'Dashboard Beispielschule <dashboard@beispielschule.de>'
DASHBOARD_SUPPORT_EMAIL = 'dashboard@beispielschule.de'

if defined? Mail
    Mail.defaults do
    delivery_method :smtp, { 
        :address => SMTP_SERVER,
        :port => 587,
        :domain => SMTP_DOMAIN,
        :user_name => SMTP_USER,
        :password => SMTP_PASSWORD,
        :authentication => 'login',
        :enable_starttls_auto => true  
    }
    end
end

# Mailing-Liste
MAILING_LIST_EMAIL = DEVELOPMENT ? 'verteiler.dev@mail.beispielschule.de' : 'verteiler@mail.beispielschule.de'
MAILING_LIST_PASSWORD = '1234_bitte_generiere_ein_zufälliges_passwort'
VERTEILER_TEST_EMAILS = ["verteiler.test@#{SCHUL_MAIL_DOMAIN}"]
VERTEILER_DEVELOPMENT_EMAILS = ['admin@beispielschule.de']
MAIL_SUPPORT_NAME = 'Mail-Support Beispielschule'
MAIL_SUPPORT_EMAIL = 'mailsupport@beispielschule.de'

# Domain, auf der die Live-Seite läuft
WEBSITE_HOST = 'dashboard.beispielschule.de'
# Name für Unterschriften in E-Mails (Mit freundlichen Grüßen...)
WEBSITE_MAINTAINER_NAME = 'Herr Müller'
WEBSITE_MAINTAINER_NAME_AKKUSATIV = 'Herrn Müller'
WEBSITE_MAINTAINER_EMAIL = 'mueller@beispielschule.de'

# Website mit Voting-System (muss noch veröffentlich werden)
VOTING_WEBSITE_URL = 'https://abstimmung.beispielschule.de'
# Ansprechpartner für Wahlverfahren
VOTING_CONTACT_EMAIL = 'admin@beispielschule.de'

# Website für Technikhilfe (Chat und Speedtest)
TECHNIK_HILFE_WEBSITE_URL = 'https://hilfe.beispielschule.de'

WEB_ROOT = DEVELOPMENT ? 'http://localhost:8025' : "https://#{WEBSITE_HOST}"

MAX_LOGIN_TRIES = 5

# Das Dashboard benötigt einen Nextcloud-Account, der Admin-Rechte hat
NEXTCLOUD_URL = 'http://localhost:8024'
# Falls die Nextcloud im Development-Modus in Docker läuft, 
# kann hier eine URL angegeben werden, unter der Nextcloud
# vom Ruby-Container aus zu erreichen ist, z. B. 'http://nextcloud'
# bei einer öffentlich erreichbaren Nextcloud-Instanz spielt es
# keine Rolle und der Wert sollte derselbe sein wie für NEXTCLOUD_URL
NEXTCLOUD_URL_FROM_RUBY_CONTAINER = 'http://nextcloud'
NEXTCLOUD_USER = 'dashboard'
NEXTCLOUD_PASSWORD = 'hunter2_bitte_etwas_anderes_waehlen'
# NEXTCLOUD_DASHBOARD_DATA_DIRECTORY muss ein absoluter Pfad sein 
NEXTCLOUD_DASHBOARD_DATA_DIRECTORY = '/var/www/html/data/dashboard'
NEXTCLOUD_WAIT_SECONDS = 0

# Das Skript share-nc-folders.rb muss sich als jeder Nutzer in der NextCloud
# anmelden können. Dazu kann die NC-App »External user authentication«
# verwendet werden, die fehlgeschlagene Anmeldeversuche an eine URL
# weiterleiten kann, die dann die Authentifizierung übernimmt.
# Wenn der folgende Wert != nil ist, ist dies das Passwort, mit dem
# sich das Skript als jeder Nutzer anmelden kann. Vorsicht ist angesagt.
#
#   'user_backends' => array(
#       array(
#           'class' => 'OC_User_BasicAuth',
#           'arguments' => array('https://dashboard.beispielschule.de/nc_auth'),
#       ),
#   ),

NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL = 'here_be_dragons_dont_use_this_password'

MATRIX_DOMAIN = 'matrix.example.com'
MATRIX_DOMAIN_SHORT = 'example.com'
MATRIX_ALL_ACCESS_PASSWORD_BE_CAREFUL = nil

MATRIX_ADMIN_USER = nil
MATRIX_ADMIN_PASSWORD = nil

MATRIX_CORPORAL_CALLBACK_BEARER_TOKEN = 'bitte_jedes_bearer_token_nur_einmal_verwenden'

# Das Dashboard vermittelt Links in Jitsi-Räume mit Hilfe von JWT 
# (JSON Web Tokens). Dafür werden ein paar Angaben benötigt,
# die auf der Jitsi-Seite verifiziert werden müssen.
JITSI_HOST = 'meet.beispielschule.de'
JWT_APPAUD = 'jitsi'
JWT_APPISS = 'dashboard'
JWT_APPKEY = 'ein_langer_langer_richtig_langer_app_key'
JWT_APPAUD_STREAM = 'stream'
JWT_APPKEY_STREAM = 'ein_langer_langer_richtig_langer_app_key'
JWT_DOMAIN_STREAM = '.beispielschule.de'
STREAM_SITE_URL = 'https://info.beispielschule.de/'
JWT_SUB = 'beispielschule.de'
# Hier kann, falls vorhanden, eine URL eingetragen werden, unter der aus dem 
# Ruby-Docker-Container ein GET-Request zu allRooms gemacht werden kann,
# der alle Räume und Teilnehmer im JSON-Format zurückgibt.
JITSI_ALL_ROOMS_URL = nil

# Es folgen ein paar Salts, die bestimmen, nach welchen Regeln
# Passwörter und sekundäre IDs generiert werden
EMAIL_PASSWORD_SALT = 'bitte_jeden_salt_nur_einmal_verwenden'
NEXTCLOUD_PASSWORD_SALT = 'bitte_jeden_salt_nur_einmal_verwenden'
KLASSEN_ID_SALT = 'bitte_jeden_salt_nur_einmal_verwenden'
USER_ID_SALT = 'bitte_jeden_salt_nur_einmal_verwenden'
LESSON_ID_SALT = 'bitte_jeden_salt_nur_einmal_verwenden'
SESSION_SCRAMBLER = 'bitte_jeden_salt_nur_einmal_verwenden'
EXTERNAL_USER_EVENT_SCRAMBLER = 'bitte_jeden_salt_nur_einmal_verwenden'
LOGIN_CODE_SALT = 'bitte_jeden_salt_nur_einmal_verwenden'
WEBSITE_READ_INFO_SECRET = 'bitte_ein_zufälliges_secret_generieren'

MESSAGE_DELAY = DEVELOPMENT ? 1 : 1
LOGIN_STATS_D = [0, 7, 28, 1000]
VPLAN_ENCODING = 'ISO-8859-1'
JITSI_EVENT_PRE_ENTRY_TOLERANCE = DEVELOPMENT ? 2880 : 15 # minutes
JITSI_EVENT_POST_ENTRY_TOLERANCE = DEVELOPMENT ? 2880 : 120 # minutes
JITSI_LESSON_PRE_ENTRY_TOLERANCE = DEVELOPMENT ? 5: 5 # minutes
JITSI_LESSON_POST_ENTRY_TOLERANCE = DEVELOPMENT ? 10: 10 # minutes
PROVIDE_CLASS_STREAM = false
COOKIE_EXPIRY_TIME = 3600 * 24 * 365
AVAILABLE_FONTS = ['Roboto', 'Alegreya']
GEN_IMAGE_WIDTHS = [2048, 1200, 1024, 768, 512, 384, 256].sort
MAINTENANCE_MODE = false
WECHSELUNTERRICHT_KLASSENSTUFEN = []
KLASSEN_TR = {'8o' => '8ω'}
TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS = 7
AUFSICHT_ZEIT = {1 => '08:00', 2 => '09:00', 3 => '09:55', 4 => '10:40',
                 6 => '12:50', 7 => '13:40', 8 => '14:30'}
PAUSENAUFSICHT_DAUER = {1 => 25, 2 => 15, 3 => 15, 4 => 20, 6 => 40, 
                        7 => 40, 8 => 15}

KLASSEN_ORDER = ['5a', '11', '12']

COLOR_SCHEME_COLORS = [
    ['la2c6e80d60aea2c6e8', 'Sky'],
    ['l307fdc03396cfe0e8d', 'Zoomer'],
]
STANDARD_COLOR_SCHEME = 'la2c6e80d60aea2c6e80'

# tablet booking pre and post time, in minutes
STREAMING_TABLET_BOOKING_TIME_PRE = 5
STREAMING_TABLET_BOOKING_TIME_POST = 15

# Liste aller E-Mail-Adressen von Nutzer*innen, 
# die Administratorenrechte haben sollen
ADMIN_USERS = ['clarke@beispielschule.de']

# List aller E-Mail-Adressen von Nutzer*innen, 
# die alle Stundenpläne sehen können sollen
CAN_SEE_ALL_TIMETABLES_USERS = []

CAN_UPLOAD_VPLAN_USERS = []

CAN_UPLOAD_FILES_USERS = []

CAN_MANAGE_NEWS_USERS = []

# Schülervertretung, kann:
# - Nachrichten an SuS schreiben
# - Umfragen unter SuS starten
# - Abstimmungen starten
SV_USERS = []

TABLET_DEFAULT_COLOR = '#d3d7cf'
TABLET_COLORS = {}

# Definition von Wechselwochen
SWITCH_WEEKS = {'2021-03-08' => ['A', 2],
                '2021-03-22' => nil}

KLASSENRAUM_ACCOUNT_DEEP_LINK_CODE = nil

def override_email_login_recipient_for_chat(email)
    email
end

DEMO_ACCOUNT_EMAIL = nil
DEMO_ACCOUNT_INFO = nil
DEMO_ACCOUNT_FIXED_PIN = nil

DEVELOPMENT_MAIL_DELIVERY_POSITIVE_LIST = []

SCHOOL_WEBSITE_API_URL = ''

UNTIS_VERTRETUNGSPLAN_BASE_URL = 'https://beispielschule.de/vertretungsplan_lehrer'
UNTIS_VERTRETUNGSPLAN_USERNAME = nil
UNTIS_VERTRETUNGSPLAN_PASSWORD = nil
