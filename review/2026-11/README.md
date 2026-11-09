# Project review November 2026

Review of the whole project from several perspectives, written by AI
agents (Claude Code) on 9 November 2026 against `master`. The agents read
code and took measurements in the test stack with example data – none of
it has been checked against real data. Findings marked “(assumption)” or
“[assumption]” are derived from the code and not reproduced.

The reports are working material, not decisions. Whatever is to be
implemented moves to [TODO.md](../../TODO.md); tick off completed items there.
Security findings are deliberately not included here (see AGENTS.md §1).

| Report | Contents |
|---|---|
| [ui-ux.md](ui-ux.md) | Usability on desktop and phone, quick wins, what can go |
| [funktionalitaet.md](funktionalitaet.md) | Bugs, stale state in the bots, mail forwarder dropouts |
| [performance.md](performance.md) | Timetable update, page renderer, database indexes, bundle |
| [devops.md](devops.md) | Deployment, images, backups, CI, Neo4j 5, startup time and hot reload |
| [monitoring.md](monitoring.md) | Health checks, silent failures, logs, alerting |
| [wartung.md](wartung.md) | Dead code, duplication, structure of main.rb/timetable.rb |
| [dokumentation.md](dokumentation.md) | Errors and gaps in doc/, configuration, end-user help |
