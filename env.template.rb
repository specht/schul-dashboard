# false kann durch (`hostname`.strip == 'YOUR_HOST') ersetzt werden
RUNNING_IN_PRODUCTION = false

# UID, wichtig für Dateirechte
UID = RUNNING_IN_PRODUCTION ? 33 : 1000

# Domain, auf der die Live-Seite läuft
WEBSITE_HOST = 'dashboard.beispielschule.de'

# E-Mail für Letsencrypt
LETSENCRYPT_EMAIL = 'admin@beispielschule.de'
