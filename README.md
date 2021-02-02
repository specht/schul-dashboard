# Schul-Dashboard

Das Schul-Dashboard wurde in den Sommerferien am Gymnasium Steglitz entwickelt.

- [Dashboard am Gymnasium Steglitz (Kurzversion für Schülerinnen und Schüler)](https://youtu.be/EGQ0Gkeu1To)
- [Dashboard am Gymnasium Steglitz (ausführliche Version für Lehrkräfte)](https://youtu.be/BYqWu9Yft8s)

## Installation

Systemvoraussetzungen: 

- ruby
- docker
- docker-compose

Bevor das Dashboard gestartet werden kann, muss es konfiguriert werden.

* `env.template.rb` als `env.rb` speichern und Werte anpassen
* `src/ruby/credentials.template.rb` als `src/ruby/credentials.rb` speichern und Werte anpassen

Das Skript `config.rb` ist ein Wrapper um `docker-compose`, der `docker-compose.yaml` erzeugt und dann `docker-compose` mit den angegebenen Argumenten aufruft.

### Bauen der Docker-Images

    ./config.rb build
    
### Start des Systems

    ./config.rb up
    
