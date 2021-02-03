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

Standardmäßig wird eine kleine Nextcloud-Sandbox mitgeliefert, die nicht für den Produktiveinsatz gedacht ist. Sie lässt sich aber gut dafür verwenden, um die Verknüpfung zwischen Dashboard und Nextcloud auszuprobieren.
