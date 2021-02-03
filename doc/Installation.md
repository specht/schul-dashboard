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

    ./config.rb build
    
## Start des Systems

    ./config.rb up
    
Das Dashboard kann nun unter [http://localhost:8025](http://localhost:8025) aufgerufen werden Damit man sich allerdings auch anmelden kann, muss das Dashboard konfiguriert werden.

