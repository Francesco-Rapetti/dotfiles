# dotfiles

Configurazione di [AeroSpace](https://github.com/nikitabobko/AeroSpace) (tiling window manager) e
[SketchyBar](https://github.com/FelixKratz/SketchyBar) (barra di stato), con i bordi delle finestre
disegnati da [JankyBorders](https://github.com/FelixKratz/JankyBorders).

```
dotfiles/
├── aerospace/aerospace.toml   → ~/.config/aerospace
└── sketchybar/                → ~/.config/sketchybar
    ├── sketchybarrc
    └── plugins/*.sh
```

Le cartelle in `~/.config` sono symlink verso questo repo: le app leggono la config dal percorso
standard, ma i file veri stanno qui.

## Setup su un Mac nuovo

### 1. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Alla fine segui le istruzioni che stampa per aggiungere `brew` al `PATH` (su Apple Silicon è in
`/opt/homebrew/bin`). L'installer porta con sé anche i Command Line Tools, quindi `git`.

### 2. Pacchetti

```bash
brew install --cask nikitabobko/tap/aerospace
brew tap FelixKratz/formulae
brew install sketchybar borders
brew install --cask font-sf-pro
```

I testi della barra usano Helvetica Neue, già presente su macOS. Le icone della rete sono
[SF Symbols](https://developer.apple.com/sf-symbols/) e servono il font SF Pro: il cask è un
installer `.pkg`, quindi chiede la password di amministratore. Senza SF Pro le icone appaiono come
riquadri vuoti.

### 3. Clona il repo

```bash
mkdir -p ~/Developer
git clone https://github.com/Francesco-Rapetti/dotfiles.git ~/Developer/dotfiles
```

Il percorso è a tua scelta, ma i comandi sotto assumono `~/Developer/dotfiles`.

### 4. Symlink

```bash
mkdir -p ~/.config
ln -s ~/Developer/dotfiles/aerospace ~/.config/aerospace
ln -s ~/Developer/dotfiles/sketchybar ~/.config/sketchybar
```

Attenzione:

- Se `~/.config/aerospace` o `~/.config/sketchybar` esistono già come cartelle, rinominale prima
  (es. `mv ~/.config/sketchybar ~/.config/sketchybar.bak`): altrimenti `ln -s` crea il link
  *dentro* la cartella esistente invece di sostituirla.
- Non deve esistere `~/.aerospace.toml`: se AeroSpace trova due config si rifiuta di caricarle.
- Collega sempre le cartelle, non i singoli file: molti editor salvano riscrivendo il file e
  romperebbero un symlink al file.

### 5. Impostazioni di macOS

Queste sono le impostazioni che uso insieme ad AeroSpace e SketchyBar:

| Impostazione | Valore | Perché |
| --- | --- | --- |
| Barra dei menu → nascondi automaticamente | Sempre | Al suo posto c'è SketchyBar |
| Barra dei menu a schermo intero | Nascosta | Idem |
| Scrivania e Dock → riorganizza gli spazi in base all'uso recente | Off | Non rimescola gli spazi di macOS |
| Scrivania e Dock → clic sullo sfondo per mostrare la scrivania | Solo in Stage Manager | Evita che un clic tra le finestre le sposti tutte |
| Scrivania e Dock → trascina le finestre sul bordo per affiancarle | Off | Il tiling nativo si scontra con AeroSpace |

Da terminale:

```bash
defaults write NSGlobalDomain _HIHideMenuBar -bool true
defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false
killall Dock
```

La barra dei menu potrebbe richiedere un logout per nascondersi.

### 6. Avvia AeroSpace

```bash
open -a AeroSpace
```

- Al primo avvio concedi il permesso di **Accessibilità** (Impostazioni di Sistema → Privacy e
  sicurezza → Accessibilità → AeroSpace).
- AeroSpace si avvia da solo al login (`start-at-login = true`) e a sua volta lancia `sketchybar`
  e `borders` (`after-startup-command` in `aerospace.toml`). **Non** attivare
  `brew services start sketchybar` o `borders`: partirebbero due istanze.

### 7. Verifica

```bash
aerospace config --config-path
```

Deve stampare `~/.config/aerospace/aerospace.toml`. In alto dovresti vedere la barra con i
workspace, l'app attiva, la rete, la batteria e l'orologio, e la finestra attiva con il bordo
sfumato.

Se la barra è vuota o mancano i workspace:

```bash
chmod +x ~/Developer/dotfiles/sketchybar/sketchybarrc ~/Developer/dotfiles/sketchybar/plugins/*.sh
sketchybar --reload
```

La rete mostra il nome del Wi-Fi, `Ethernet` quando c'è un cavo, `Non connesso` (giallo) o
`Wi-Fi off` (rosso). Da macOS 14.4 il nome del Wi-Fi è oscurato in `networksetup`, `ipconfig` e
`system_profiler`: `plugins/network.sh` lo legge dall'ultima scansione salvata nella configurazione
di sistema. Se un aggiornamento di macOS chiude anche questa strada, al posto del nome compare
`Wi-Fi`.

## Da adattare al nuovo Mac

In `aerospace/aerospace.toml`:

- **`gaps.outer.top`**: `40` = altezza di SketchyBar (32) + 8. Il display integrato ha `2` perché
  sui MacBook con notch macOS riserva già lo spazio in alto. Su un Mac senza notch usa `40` anche
  per il display integrato.
- **`[workspace-to-monitor-force-assignment]`**: il workspace 1 va sul monitor principale, il 2 sul
  secondario.
- **`[[on-window-detected]]`**: regole che spostano le app nei workspace (WhatsApp, Telegram, Mail
  → 9; Teams, Slack → 8; Spotify, Chrome → 2). Per trovare l'id di un'app:
  `osascript -e 'id of app "Nome App"'`.

## Scorciatoie principali

| Tasti | Azione |
| --- | --- |
| `alt-1` … `alt-9` | Vai al workspace |
| `alt-shift-1` … `alt-shift-9` | Sposta la finestra nel workspace |
| `alt-a/s/w/d` | Focus sinistra/giù/su/destra |
| `alt-shift-a/s/w/d` | Sposta la finestra |
| `alt-shift-h/j/k/l` | Unisci con la finestra a sinistra/giù/su/destra |
| `alt-/` · `alt-,` | Layout tiles · accordion |
| `alt--` · `alt-=` | Ridimensiona |
| `alt-tab` | Workspace precedente |
| `alt-shift-tab` | Sposta il workspace sul monitor successivo |
| `alt-enter` | Apri Terminal |
| `alt-f` | Fullscreen |
| `alt-shift-space` | Finestra floating/tiling |
| `alt-backspace` | Chiudi la finestra |
| `alt-shift-;` | Modalità *service* (`esc` ricarica la config, `r` resetta il layout, `f` floating, `backspace` chiude le altre finestre, `↑`/`↓` volume) |

## Modificare la config

Modifica i file in `~/Developer/dotfiles` (o tramite i symlink in `~/.config`), poi ricarica:

```bash
aerospace reload-config
sketchybar --reload
```

Infine `git commit` e `git push` come in qualsiasi repo.
