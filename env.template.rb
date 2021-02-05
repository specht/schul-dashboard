# ------------------------------------------------------
# Achtung: Wenn diese Datei verändert wurde, muss erneut
# ./config.rb build ausgeführt werden.
# ------------------------------------------------------

# für Produktionsumgebungen bitte auf false setzen
DEVELOPMENT = true

# Präfix für Docker-Container-Namen
PROJECT_NAME = 'schuldashboard' + (DEVELOPMENT ? 'dev' : '')

# UID für Prozesse, muss in Produktionsumgebungen vtml. auf einen konkreten Wert gesetzt werden
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

# Der Mail-Forwarder ist ein Skript, das einen Mail-Verteiler implementiert.
ENABLE_MAIL_FORWARDER = false

# Der Image Bot generiert verkleinerte Versionen von hochgeladenen Bildern
# im jpeg- und webp-Format.
ENABLE_IMAGE_BOT = false

# NextCloud für Test- und Entwicklungszwecke starten?
# Bitte so nicht für den Produktiveinsatz nutzen
# (läuft z. B. mit SQLite und skaliert schlecht)
ENABLE_NEXTCLOUD_SANDBOX = true
NEXTCLOUD_SANDBOX_INSTALL_ADMIN_USER = 'dashboard'
NEXTCLOUD_SANDBOX_INSTALL_ADMIN_PASSWORD = 'hunter2_bitte_etwas_anderes_waehlen'
