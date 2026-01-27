*GPT-5 Answer*


---

### Bootstrap eines neuen Systems (Einzeiler)
Auf dem neuen Server

`sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <dein-repo-url-oder-github-user>`

**mit Repo-URL**

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/mounta11n/dotfiles.git
```

**nur mit GitHub-User (Repo heißt dann “dotfiles”)**

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply mounta11n
```

---

### Scripts für Erst-Einrichtung
- Lege in deinem chezmoi-Source Verzeichnis “run”-Skripte an, z.B.:
  - run_once_*.sh(.tmpl): wird beim ersten apply ausgeführt
  - run_*.sh(.tmpl): wird bei jedem apply ausgeführt
  - run_onchange_*.sh(.tmpl): nur wenn sich der Inhalt geändert hat
  - Optional before_/after_ für Reihenfolge (run_once_before_..., run_after_...)
- Die Skripte dürfen templated sein (.tmpl), sodass du OS/Host-spezifisch agieren kannst.

---

### Debian/Ubuntu

#### Grundsetup

Datei: `scripts/run_once_10_apt.sh.tmpl`

```sh
#!/bin/sh
set -e
if [ "{{ .chezmoi.os }}" = "linux" ] && command -v apt >/dev/null 2>&1; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    zsh git curl ca-certificates build-essential
fi
```

---

#### Zsh als Default-Shell

Datei: `scripts/run_once_20_set-zsh.sh.tmpl`

```sh
#!/bin/sh
set -e
if command -v zsh >/dev/null 2>&1; then
  zsh_path="$(command -v zsh)"
  if [ "$SHELL" != "$zsh_path" ]; then
    sudo chsh -s "$zsh_path" "$(id -un)"
  fi
fi
```

---

#### oh-my-zsh holen (per .chezmoiexternal oder Script)

##### Variante A

> .chezmoiexternal.toml (Empfehlung: idempotent, versionsfest)

Datei `.chezmoiexternal.toml`

```sh
[".oh-my-zsh"]
type = "git"
url = "https://github.com/ohmyzsh/ohmyzsh.git"
branch = "master"
path = "~/.oh-my-zsh"
```

*Bei apply lädt/aktualisiert chezmoi das Repo nach ~/.oh-my-zsh.*

##### Variante B

> Script

Datei `scripts/run_once_30_install-omz.sh`

```sh
#!/bin/sh
set -e
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  git clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
fi
```

---

### Konfiguration templatieren (macOS, Linux, ...)

*Deine ~/.zshrc als dot_zshrc.tmpl verwalten und z.B. Plugins abhängig von OS/Host setzen*

```sh
{{- if eq .chezmoi.os "darwin" -}}
# macOS-spezifische Settings …
{{- else if eq .chezmoi.os "linux" -}}
# Linux-spezifische Settings …
{{- end }}
```


#### OS-/Host-spezifisch

- Nutze Template-Variablen:
  - .chezmoi.os (darwin, linux, windows, …)
  - .chezmoi.arch
  - .chezmoi.hostname
- Oder definiere eigene Daten in .chezmoi.toml.tmpl:

```sh
[data]
  role = "server"  # oder "laptop"
Und in Skripten/Files:
{{ if eq .role "server" }} … {{ end }}
```

---

### Externe Artefakte und Binärdateien

- Mit .chezmoiexternal kannst du auch Archive/Binaries holen:
["bin/fd"]
type = "archive"
url = "https://github.com/sharkdp/fd/releases/download/v9.0.0/fd-v9.0.0-x86_64-unknown-linux-gnu.tar.gz"
stripComponents = 1
path = "~/.local/bin"

Sicherheit/Secrets
- Chezmoi integriert age/GPG. Geheimnisse als *.tmpl rendern und lokal entschlüsseln:
  - z.B. dot_config/myapp/creds.tmpl liest {{ (include "secret age:…" | trim) }}
  - So landen keine Secrets im Klartext im Repo.

Typischer Ablauf auf dem neuen Hetzner-VPS
- Als User mit sudo:
  sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/user/dotfiles.git
- chezmoi:
  - installiert Dotfiles
  - führt run_once_*-Skripte aus (apt, zsh, oh-my-zsh)
  - lädt Externals (oh-my-zsh, Binaries) gemäß .chezmoiexternal
- Danach ggf. erneut:
  chezmoi apply -v
  um geänderte Templates/Skripte erneut anzuwenden.

Tipps
- Idempotenz: Skripte so schreiben, dass mehrfaches apply keine Fehler verursacht.
- Reihenfolge: 10_, 20_, 30_… in Dateinamen helfen bei der Sortierung.
- Interaktivität vermeiden (DEBIAN_FRONTEND=noninteractive, chsh nur ausführen wenn nötig).
- Tags/Rollen: Über .chezmoi.toml(.tmpl) ein “role” setzen und in Templates/Skripten darauf prüfen.
- macOS/Homebrew: Analog per run_once_… brew installieren und Brewfile anwenden.
- Testen: Auf einer frischen VM/Container testen, dann auf dem produktiven VPS verwenden.

Wenn du magst, poste dein Repo-Aufbau, dann skizziere ich dir konkrete Dateien für deine Ziele (apt‑Pakete, zsh/oh‑my‑zsh, SSH‑Härtung, Fail2ban, etc.).
