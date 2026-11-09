# Projekt-Review November 2026

Durchsicht des ganzen Projekts aus mehreren Blickwinkeln, erstellt von
KI-Agenten (Claude Code) am 9. November 2026 auf Stand `master`. Die
Agenten haben Code gelesen und im Test-Stack mit Beispieldaten gemessen –
nichts davon ist gegen echte Daten geprüft. Befunde mit „(Vermutung)“ oder
„[Annahme]“ sind aus dem Code abgeleitet und nicht reproduziert.

Die Berichte sind Arbeitsmaterial, keine Beschlüsse. Was umgesetzt werden
soll, wandert nach [TODO.md](../../TODO.md); Erledigtes dort abhaken.
Sicherheitsbefunde stehen bewusst nicht hier (siehe AGENTS.md §1).

| Bericht | Inhalt |
|---|---|
| [ui-ux.md](ui-ux.md) | Bedienung auf Desktop und Handy, Quick Wins, was weg kann |
| [funktionalitaet.md](funktionalitaet.md) | Fehler, veralteter Zustand in den Bots, Mail-Forwarder-Aussetzer |
| [performance.md](performance.md) | Stundenplan-Update, Seiten-Renderer, Datenbank-Indizes, Bundle |
| [devops.md](devops.md) | Deployment, Images, Backups, CI, Neo4j 5, Startzeit und Hot Reload |
| [monitoring.md](monitoring.md) | Healthchecks, stille Ausfälle, Logs, Alarmierung |
| [wartung.md](wartung.md) | Toter Code, Doppelungen, Struktur von main.rb/timetable.rb |
| [dokumentation.md](dokumentation.md) | Fehler und Lücken in doc/, Konfiguration, Endnutzer-Hilfe |
