# für Produktionsumgebungen bitte auf false setzen
DEVELOPMENT = true

# Präfix für Docker-Container-Namen
PROJECT_NAME = 'schuldashboard' + (DEVELOPMENT ? 'dev' : '')

# UID für Prozesse
UID = 1000

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
