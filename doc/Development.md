# Entwicklerhandbuch

Im Development-Modus startet sich der Ruby-Server automatisch neu, sobald eine Ruby-Datei verändert wird. Wenn man dann F5 im Browser drückt, bevor der Server bereit ist, wird man mit einem »502 Bad Gateway« belohnt, der für 10 Sekunden anhält (scheint Sinatra-typisch zu sein, sicherlich gibt es gute Gründe dafür). Änderungen an HTML-, CSS- und JS-Dateien erfordern keinen Neustart, da sie immer neu geladen werden.
