# Installation

Systemvoraussetzungen: 

- ruby
- docker
- docker-compose

Bevor das Dashboard gestartet werden kann, muss es konfiguriert werden.

* `env.template.rb` als `env.rb` speichern und Werte anpassen
* `src/ruby/credentials.template.rb` als `src/ruby/credentials.rb` speichern und Werte anpassen

Es reicht für einen ersten Test, die Dateien so zu lassen, wie sie sind.

Das Skript `config.rb` ist ein Wrapper um `docker-compose`, der `docker-compose.yaml` erzeugt und dann `docker-compose` mit den angegebenen Argumenten aufruft.

## Bauen der Docker-Images

    $ ./config.rb build
    
## Start des Systems

    $ ./config.rb up
    
Nun können folgende Seiten aufgerufen werden:

- Dashboard: [http://localhost:8025](http://localhost:8025)
- Neo4j: [http://localhost:8021](http://localhost:8021)
- Nextcloud-Sandbox: [http://localhost:8024](http://localhost:8024)

Da es in den mitgelieferten Beispieldaten schon einen Lehrer gibt, kann man sich nun im Dashboard ([http://localhost:8025](http://localhost:8025)) anmelden als `clarke@beispielschule.de`. Da standardmäßig kein E-Mail-Server konfiguriert ist, muss man den Zahlencode aus den Logs holen:

    ruby_1            | !!!!! clarke@beispielschule.de => 224529 !!!!!
    ruby_1            | Cannot send e-mail in DEVELOPMENT mode, continuing anyway:
    ruby_1            | getaddrinfo: Name does not resolve
    
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
    
Das Skript kann jederzeit erneut gestartet werden, wenn Nutzer dazukommen.
    
### Erstellen der Nextcloud-Ordner

    $ ./create-nc-folders.rb
    
Das Skript kann jederzeit erneut gestartet werden, wenn Fächer dazukommen.

### Teilen der Nextcloud-Ordner

    $ ./share-nc-folders.rb
    
Das Skript kann jederzeit erneut gestartet werden, wenn sich die Zuordnung von Fächern zu Lehrern oder Schülern verändert.

Für dieses Skript wird die App »user_external« in Nextcloud benötigt, da sich das Skript als der jeweilige Nutzer anmelden muss, um einen geteilten Ordner ins richtige Verzeichnis zu verschieben. Damit das in der Nextcloud-Sandbox funktioniert, haben wir weiter oben das Skript `install-nextcloud-sandbox.rb` ausgeführt. **Achtung:** Solange diese App aktiviert ist und die Nextcloud so konfiguriert ist, dass diese App auch verwendet wird, gibt es ein Blanko-Passwort, mit jeder in jeden Account kommt: `NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL`.

