# ------------------------------------------------------------------
# Umgebung für den isolierten Test-Stack (siehe doc/Tests.md).
# Wird von ./test.sh über DASHBOARD_ENV=env.test.rb verwendet.
#
# - nur Beispieldaten (src/example-data), nie echte Schuldaten
# - eigener Projektname, eigene Compose-Datei, eigene Daten unter
#   .test-stack/ – eine laufende Entwicklungsinstanz bleibt unberührt
# - nginx nur auf 127.0.0.1:8125, keine weiteren Ports
# ------------------------------------------------------------------

# Development-Modus: feste Anmeldecodes (123456 / 654321). Das ist nur
# vertretbar, weil hier ausschließlich Beispieldaten verwendet werden.
DEVELOPMENT = true

PROJECT_NAME = 'schuldashboardtest'
UID = Process::UID.eid

WEBSITE_HOST = 'dashboard.test.invalid'
LETSENCRYPT_EMAIL = 'admin@test.invalid'

INPUT_DATA_PATH = './src/example-data'
LOGS_PATH = './.test-stack/logs'
DATA_PATH = './.test-stack/data'
INTERNAL_PATH = './.test-stack/internal'

NEXTCLOUD_INSTALL_PATH = nil
NEXTCLOUD_PHP_COMMAND = ['true']

ENABLE_MAIL_FORWARDER = false
ENABLE_IMAGE_BOT = false
ENABLE_NEXTCLOUD_SANDBOX = false
NEXTCLOUD_SANDBOX_INSTALL_ADMIN_USER = 'dashboard'
NEXTCLOUD_SANDBOX_INSTALL_ADMIN_PASSWORD = 'unused'

DOCKER_NETWORK_NAME = :dashboard
DOCKER_NETWORK_SUBNET = nil
DOCKER_NETWORK_RUBY_IP = nil

# Optionale Einstellungen, die config.rb auswertet
COMPOSE_FILE = 'docker-compose.test.yaml'
NGINX_CONFIG_FILE = 'docker/nginx/default.test.conf'
# muss zu WEB_ROOT in src/ruby/test/credentials.rb passen
NGINX_HOST_PORT = 8125
NGINX_HOST_ADDRESS = '127.0.0.1'
PUBLISH_DEV_PORTS = false
CREDENTIALS_FILE = './test/credentials.rb'
