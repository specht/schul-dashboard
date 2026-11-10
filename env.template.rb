# ------------------------------------------------------
# Achtung: Nach Änderungen an dieser Datei reicht meist
# ./config.rb up -d (erzeugt docker-compose.yaml neu);
# ./config.rb build nginx zusätzlich, wenn sich dadurch die
# erzeugte nginx-Konfiguration ändert (z. B. PROJECT_NAME).
# ------------------------------------------------------

# für Produktionsumgebungen bitte auf false setzen
DEVELOPMENT = true

# Präfix für Docker-Container-Namen
PROJECT_NAME = 'schuldashboard' + (DEVELOPMENT ? 'dev' : '')

# UID für Prozesse, muss in Produktionsumgebungen evtl. auf einen konkreten Wert gesetzt werden
UID = Process::UID.eid

# Domain, auf der die Live-Seite läuft
WEBSITE_HOST = 'dashboard.beispielschule.de'

# E-Mail für Letsencrypt
LETSENCRYPT_EMAIL = 'admin@beispielschule.de'

# Pfad mit Verzeichnissen für Stundenplan, SuS-Listen, etc
INPUT_DATA_PATH = './src/example-data'

# Diese Pfade sind für Development okay und sollten für
# Produktionsumgebungen angepasst werden
LOGS_PATH = './logs'
DATA_PATH = './data'
INTERNAL_PATH = './internal'

# Für native Änderungen des Zielpfads empfangener Nextcloud-Shares benötigt
# share-nc-folders.rb Zugriff auf die lokale Nextcloud-Installation.
# In Produktionsumgebungen z. B. '/www/vhosts/nextcloud'.
NEXTCLOUD_INSTALL_PATH = nil
NEXTCLOUD_PHP_COMMAND = ['sudo', '--user', 'www-data', '/usr/bin/php']

# Der Mail-Forwarder ist ein Skript, das einen Mail-Verteiler implementiert.
ENABLE_MAIL_FORWARDER = false

# Der Image Bot generiert verkleinerte Versionen von hochgeladenen Bildern
# im jpeg- und webp-Format.
ENABLE_IMAGE_BOT = true

# Nextcloud für Test- und Entwicklungszwecke starten?
# Bitte so nicht für den Produktiveinsatz nutzen
# (läuft z. B. mit SQLite und skaliert schlecht)
ENABLE_NEXTCLOUD_SANDBOX = true
NEXTCLOUD_SANDBOX_INSTALL_ADMIN_USER = 'dashboard'
NEXTCLOUD_SANDBOX_INSTALL_ADMIN_PASSWORD = 'hunter2_bitte_etwas_anderes_waehlen'

DOCKER_NETWORK_NAME = :dashboard

# Falls gewünscht, kann hier das Subnetz und die IP-Adresse des Ruby-Containers
# definiert werden
DOCKER_NETWORK_SUBNET = nil
DOCKER_NETWORK_RUBY_IP = nil

# Container-Logs rotieren (sonst behält Docker sie unbegrenzt). Empfohlen;
# auskommentieren, um wie früher ohne Begrenzung zu loggen.
DOCKER_LOG_MAX_SIZE = '50m'
DOCKER_LOG_MAX_FILES = 5

# Nur Entwicklung: geänderte src/ruby/include/*.rb werden bei der nächsten
# Anfrage neu geladen statt den Server neu zu starten (Standard, siehe
# doc/Development.md). Zum Abschalten:
# DEV_HOT_RELOAD = false

# Nur Entwicklung: Server für src/scripts/pull-prod-data.rb, das die
# Produktionsdaten in die Entwicklungsinstanz holt (Name aus ~/.ssh/config).
# PROD_SSH_HOST = 'mein-server'
# PROD_CHECKOUT_PATH = 'dashboard'   # Verzeichnis des Checkouts, relativ zum Home
