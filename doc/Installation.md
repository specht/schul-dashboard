# Installation

Systemvoraussetzungen: 

- ruby
- docker mit Compose (`docker compose`; das ältere `docker-compose` funktioniert auch)

Bevor das Dashboard gestartet werden kann, muss es konfiguriert werden.

* `env.template.rb` als `env.rb` speichern und Werte anpassen
* `src/ruby/credentials.template.rb` als `src/ruby/credentials.rb` speichern und Werte anpassen

Es reicht für einen ersten Test, die Dateien so zu lassen, wie sie sind, also

    $ cp env.template.rb env.rb
    $ cp src/ruby/credentials.template.rb src/ruby/credentials.rb 

Das Skript `config.rb` ist ein Wrapper um Docker Compose: Es erzeugt `docker-compose.yaml` und ruft dann `docker compose` mit den angegebenen Argumenten auf.

## Schlüssel für das Single Sign-on

Nach der Anmeldung signiert das Dashboard ein Cookie mit einem eigenen
Schlüsselpaar. Fehlt es, endet jede Seite nach der Anmeldung mit einem Fehler.
Einmalig erzeugen (Pfad: `INTERNAL_PATH` aus `env.rb`, standardmäßig
`./internal`):

    $ mkdir -p internal/sso-keys
    $ openssl ecparam -name prime256v1 -genkey -noout -out internal/sso-keys/sso_private.pem
    $ openssl ec -in internal/sso-keys/sso_private.pem -pubout -out internal/sso-keys/sso_public.pem

## Bauen der Docker-Images

    $ ./config.rb build
    
## Start des Systems

    $ ./config.rb up
    
Mit der Option `-d` läuft das System im Hintergrund; ohne sie sieht man die Logs aller Dienste direkt in der Konsole.
    
Nun können folgende Seiten aufgerufen werden:

- Dashboard: [http://localhost:8025](http://localhost:8025)
- Neo4j: [http://localhost:8021](http://localhost:8021)
- Nextcloud-Sandbox: [http://localhost:8024](http://localhost:8024)

Da es in den mitgelieferten Beispieldaten schon einen Lehrer gibt, kann man sich nun im Dashboard ([http://localhost:8025](http://localhost:8025)) anmelden als `clarke@beispielschule.de`. Im Development-Modus ist der Anmeldecode immer `123456` und ein zweiter Faktor `654321` – eine E-Mail wird dafür nicht gebraucht (siehe [Entwicklerhandbuch](file.Development.html)).

Für den Betrieb an einer Schule siehe [Betrieb](file.Betrieb.html).
    
## Schreiben der Stundenpläne

Der Stundenplan ist momentan noch leer und muss einfach mit folgendem Befehl befüllt werden:

    $ cd src/scripts
    $ ./update-timetables.rb
    
In den Logs kann man beobachten, wie die Stundenpläne geschrieben werden:

    timetable_1       | Fetched 0 updated lesson events, 0 updated text comments, 0 updated audio comments, 0 updated messages and 0 updated events.
    timetable_1       | Updating weeks: 
    timetable_1       | ...........................................................
    timetable_1       | <<< Finished updating all in 0.47 seconds, wrote 531 files.
    timetable_1       | -----------------------------------------------------------

Dabei wird für jeden Nutzer und jede Woche eine Datei geschrieben, die der Browser später lädt, um die aktuellen Daten anzuzeigen.

Die Stundenpläne der betroffenen Teilnehmer werden im späteren Verlauf jedesmal, wenn Informationen zu einer Unterrichtsstunde verändert werden, neu geschrieben.

Zu den Beispieldaten und zur Pflege neuer Daten gibt es [hier weitere Informatonen](file.Daten.html).

## Starten der Nextcloud-Sandbox

Standardmäßig wird eine kleine Nextcloud-Sandbox mitgeliefert, die nicht für den Produktiveinsatz gedacht ist. Sie lässt sich aber gut dafür verwenden, um die Verknüpfung zwischen Dashboard und Nextcloud auszuprobieren. Dazu muss zunächst die Installation der Nextcloud-Sandbox abgeschlossen werden:

    $ ./install-nextcloud-sandbox.rb 
    Installing user_external app in Sandbox Nextcloud...
    user_external 1.0.0 installed
    user_external enabled
    Activating HTTP Basic Authentication Fallback for Sandbox Nextcloud...

Es wurde nun HTTP-Basic-Authentication aktiviert. Dies wird später vorübergehend benötigt, wenn das Dashboard die individuellen Nextcloud-Ordner an die einzelnen Nutzer:innen freigibt.

Die Anbindung an Nextcloud erfolgt in drei Schritten:

### Erstellen der Nextcloud-Nutzer

    $ cd src/scripts
    $ ./create-nc-users.rb

**Bitte die "Notice" in der Ausgabe beachten**: Das Log zeigt erstmal 
nur, welche Änderungen das Skript ausführen möchte. Um diese Änderungen 
tatsächlich durchzuführen, muss es wie folgt gestartet werden:

    $  ./create-nc-users.rb --srsly
    
Das Skript kann jederzeit erneut gestartet werden, wenn Nutzer dazukommen.
    
### Erstellen der Nextcloud-Ordner

    $ ./create-nc-folders.rb
    
**Bitte auch hier den Hinweis in der Ausgabe beachten**: Auch diese 
Befehle wurden nicht direkt ausgeführt, können aber in der Testumgebung 
an den Docker-Container übergeben werden:

    $ ./create-nc-folders.rb | (cd ../.. && ./config.rb exec -T nextcloud bash -)

Im Ergebnis sieht man, dass unterhalb eines Ordners `Unterricht` verschiedene Ordner für für die Klassen/Kurse, Fächer und Schüler angelegt wurden.
    
    mkdir: created directory '/var/www/html/data/dashboard/files/Unterricht/Nawi~6a/SuS/Max Mustermann/Einsammelordner'
    mkdir: created directory '/var/www/html/data/dashboard/files/Unterricht/Nawi~6a/SuS/Max Mustermann/Einsammelordner/Eingesammelt'
    mkdir: created directory '/var/www/html/data/dashboard/files/Unterricht/Nawi~6a/SuS/Max Mustermann/R'$'\303\274''ckgabeordner'
    Starting scan for user 1 out of 1 (dashboard)
    +---------+-------+--------------+
    | Folders | Files | Elapsed time |
    +---------+-------+--------------+
    | 53      | 17    | 00:00:02     |
    +---------+-------+--------------+

Das Skript kann jederzeit erneut gestartet werden, wenn Fächer dazukommen.

### Teilen der Nextcloud-Ordner

    $ ./share-nc-folders.rb
    
Das Skript kann jederzeit erneut gestartet werden, wenn sich die Zuordnung von Fächern zu Lehrern oder Schülern verändert.

Ohne `--srsly` zeigt das Skript nur, was es tun würde. Mit `--srsly` verschiebt es die geteilten Ordner direkt in Nextcloud: Dazu startet es auf dem Rechner, auf dem Nextcloud installiert ist, `src/scripts/nextcloud-share-move-worker.php` (standardmäßig mit `sudo --user www-data /usr/bin/php`, anpassbar über `NEXTCLOUD_PHP_COMMAND`). Dafür muss in `env.rb` `NEXTCLOUD_INSTALL_PATH` auf die Nextcloud-Installation zeigen – in der Vorlage ist der Wert `nil`, dann bricht das Skript mit einem Hinweis ab. Mit der Sandbox lässt sich dieser Schritt deshalb nicht ohne Weiteres ausprobieren.

Die App »user_external«, die `install-nextcloud-sandbox.rb` weiter oben installiert hat, nutzen andere Skripte (z. B. `create-nc-users.rb`), um sich als der jeweilige Nutzer anzumelden. **Achtung:** Solange diese App aktiviert ist und die Nextcloud so konfiguriert ist, dass diese App auch verwendet wird, gibt es ein Blanko-Passwort, mit jeder in jeden Account kommt: `NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL`.

