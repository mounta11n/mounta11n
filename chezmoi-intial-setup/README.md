Scripts für Erst-Einrichtung
Lege in deinem chezmoi-Source Verzeichnis “run”-Skripte an, z.B.:
run_once_*.sh(.tmpl): wird beim ersten apply ausgeführt
run_*.sh(.tmpl): wird bei jedem apply ausgeführt
run_onchange_*.sh(.tmpl): nur wenn sich der Inhalt geändert hat
Optional before_/after_ für Reihenfolge (run_once_before_..., run_after_...)
Die Skripte dürfen templated sein (.tmpl), sodass du OS/Host-spezifisch agieren kannst.
