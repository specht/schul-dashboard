# Schul-Dashboard

Das Schul-Dashboard wurde am [Gymnasium Steglitz](https://gymnasiumsteglitz.de/) entwickelt, ursprünglich als Einstiegspunkt für den Distanzunterricht. Heute nutzen es Lehrkräfte, Schüler:innen und Eltern dort jeden Tag für den Schulalltag.

[![](https://img.youtube.com/vi/u4iO_B5rMf0/maxresdefault.jpg)](https://youtu.be/u4iO_B5rMf0 "E-Learning am Gymnasium Steglitz")

Es gibt ein paar Videos, die noch detaillierter zeigen, worum es dabei geht:

- [Dashboard am Gymnasium Steglitz (Kurzversion für Schülerinnen und Schüler)](https://youtu.be/EGQ0Gkeu1To)
- [Dashboard am Gymnasium Steglitz (ausführliche Version für Lehrkräfte)](https://youtu.be/BYqWu9Yft8s)

Presse:

- [14.01.2021 Tagesspiegel Leute](https://leute.tagesspiegel.de/steglitz-zehlendorf/unter-nachbarn/2021/01/14/155025/)
- [02.02.2021 RBB Inforadio](https://www.inforadio.de/programm/schema/sendungen/aktuell/202102/08/gute-idee-corona-gymnasium-plattform.html)

## Features

- jeder Teilnehmer sieht seinen aktuellen Stundenplan
  - für jede Stunde können von der Lehrkraft Themen und Aufgaben hinterlegt werden
- Anbindung an Nextcloud und Jitsi
- Daten zu Stundenplänen, Vertretungsplänen, Pausenaufsichtsplänen, Kurswahlen werden aus CSV-Dateien gelesen, die aus WinSchule oder Untis exportiert werden
- Anmeldung ohne Passwort, dafür mit Zahlencode, der per E-Mail versendet wird oder alternativ per OTP
- mit Hilfe eines persönlichen iCal-Links kann der aktuelle Dashboard-Stundenplan in andere Kalender eingebunden werden
- Sitzplanhelfer: wunschbasierter Sitzplan-Assistent, bei dem SuS per Umfrage Sitzwünsche angeben und die Lehrkraft Zwangsvorgaben, Trefferquote und eine Historie gespeicherter Pläne im Blick behält
- außerdem u. a. Nachrichten, Termine, Umfragen, Kursplanung, Klassenarbeiten, Bibliothek, Zeugnisse, Projekttage und Monitore für Vertretungsplan und Raumbuchungen

## Schnellstart

[![](https://img.youtube.com/vi/n_n6gJdkBxY/maxresdefault.jpg)](https://youtu.be/n_n6gJdkBxY "Starte dein eigenes Schul-Dashboard in 6 Minuten")

## Dokumentation

Es gibt eine ausführliche [Dokumentation](https://specht.github.io/schul-dashboard/), die Quellen liegen in [`doc/`](doc/).

Wer am Code mitarbeitet: Die verbindlichen Regeln stehen in [AGENTS.md](AGENTS.md), die Tests (`./test.sh all`) sind in [doc/Tests.md](doc/Tests.md) beschrieben.

## Lizenz

[GNU GPL v3](LICENSE)
