# dotfiles

Configurazione di [AeroSpace](https://github.com/nikitabobko/AeroSpace) (tiling window manager) e
[SketchyBar](https://github.com/FelixKratz/SketchyBar) (barra di stato), con i bordi delle finestre
disegnati da [JankyBorders](https://github.com/FelixKratz/JankyBorders).

```
dotfiles/
├── Brewfile                   (i pacchetti Homebrew)
├── aerospace/aerospace.toml   → ~/.config/aerospace
└── sketchybar/                → ~/.config/sketchybar
    ├── sketchybarrc
    ├── plugins/*.sh
    └── helpers/*.swift, *.plist, *.js  (compilati o eseguiti da sketchybarrc)
```

Le cartelle in `~/.config` sono symlink verso questo repo: le app leggono la config dal percorso
standard, ma i file veri stanno qui.

## Setup su un Mac nuovo

### 1. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Alla fine segui le istruzioni che stampa per aggiungere `brew` al `PATH` (su Apple Silicon è in
`/opt/homebrew/bin`). L'installer porta con sé anche i Command Line Tools, quindi `git` e
`swiftc`.

### 2. Pacchetti

```bash
brew install --cask nikitabobko/tap/aerospace
brew tap FelixKratz/formulae
brew install sketchybar borders terminal-notifier
brew install --cask font-sf-pro
```

I testi della barra usano Helvetica Neue, già presente su macOS. Le icone di rete e audio sono
[SF Symbols](https://developer.apple.com/sf-symbols/) e servono il font SF Pro: il cask è un
installer `.pkg`, quindi chiede la password di amministratore. Senza SF Pro le icone appaiono come
riquadri vuoti.

Gli stessi pacchetti sono elencati nel `Brewfile`: SketchyBar mostra gli aggiornamenti solo di
quelli, quindi se ne aggiungi uno aggiungilo anche lì.

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
workspace, l'app attiva, l'uscita e l'ingresso audio, la rete, la batteria, l'uso di Claude, il
prossimo evento del calendario, l'orologio e, se ci sono aggiornamenti, il loro pallino all'estrema
destra, e la finestra attiva con il bordo sfumato.

Se la barra è vuota o mancano i workspace:

```bash
chmod +x ~/Developer/dotfiles/sketchybar/sketchybarrc ~/Developer/dotfiles/sketchybar/plugins/*.sh
sketchybar --reload
```

Ogni workspace mostra il numero seguito dall'icona di ciascuna delle sue finestre, la stessa del
Dock: tre finestre di VS Code sono tre icone. Quello attivo è evidenziato insieme alle sue icone, e
quelli vuoti non compaiono. Un clic sul numero apre il workspace, un clic su un'icona porta a quella
finestra. Le app senza bundle id mostrano l'iniziale del nome. Le icone si aggiornano quando una
finestra si apre, si chiude o cambia workspace: per questo `aerospace.toml` avvisa SketchyBar a ogni
cambio di focus (`on-focus-changed`) e con `alt-shift-1` … `alt-shift-9`.

La rete mostra il nome del Wi-Fi, `Ethernet` quando c'è un cavo, `Non connesso` (giallo) o
`Wi-Fi off` (rosso). Da macOS 14.4 il nome del Wi-Fi è oscurato in `networksetup`, `ipconfig` e
`system_profiler`: `plugins/network.sh` lo legge dall'ultima scansione salvata nella configurazione
di sistema. Se un aggiornamento di macOS chiude anche questa strada, al posto del nome compare
`Wi-Fi`.

L'audio mostra il dispositivo di uscita e quello di ingresso predefiniti, con un'icona per tipo
(altoparlanti, cuffie, headset, AirPods, occhiali audio, monitor, AirPlay, microfono). Se sono lo
stesso dispositivo, per esempio cuffie Bluetooth, compaiono le due icone e il nome una volta sola.
macOS non ha un comando da terminale per leggerli, quindi `sketchybarrc` compila
`helpers/audio_devices.swift` al primo avvio (e ogni volta che il sorgente cambia) e lo lascia in
ascolto per aggiornare la barra appena cambi dispositivo. Il binario compilato non è nel repo. Se
l'audio non compare, compilalo a mano per vedere l'errore:

```bash
swiftc -O ~/Developer/dotfiles/sketchybar/helpers/audio_devices.swift -o ~/Developer/dotfiles/sketchybar/helpers/audio_devices
```

Il calendario mostra il prossimo evento della giornata (`14:30  Riunione`). Mentre un evento è in
corso mostra quello (`Riunione · fino alle 15:00`), a meno che il successivo non inizi prima che
finisca. Quando non restano eventi con orario compaiono quelli di tutto il giorno, e se non ci sono
neanche quelli l'elemento sparisce. Legge tutti i calendari dell'app Calendario, tranne gli eventi
annullati o rifiutati, e un clic apre Calendario. macOS concede l'accesso al calendario solo
all'app che lo chiede, quindi `sketchybarrc` compila `helpers/calendar_events.swift` in una piccola
app senza icona nel Dock, `helpers/calendar_events.app` (non è nel repo), e la avvia con `open`.
Al primo avvio macOS chiede l'accesso ai calendari per **SketchyBar Calendar**: scegli *Consenti*.
Se l'hai negato, al posto dell'evento compare `Nessun accesso al calendario` in rosso: attiva
SketchyBar Calendar in Impostazioni di Sistema → Privacy e sicurezza → Calendari, poi
`sketchybar --reload`.

I testi seguono la lingua del Mac (italiano o inglese, per le altre lingue inglese) e gli orari il
formato della sua regione, 12 o 24 ore compreso. Anche l'orologio mostra il giorno della settimana
nella lingua del Mac (`mer 30/09  14:30`).

Un clic sull'orologio apre il mese corrente, con oggi evidenziato, la settimana che parte dal
giorno scelto in Impostazioni di Sistema → Generali → Lingua e Zona e i weekend più tenui; un clic
sul mese apre Calendario. SketchyBar non sa disporre gli elementi di un popup in una griglia, quindi
il mese è un'immagine che `helpers/calendar_month.swift` disegna ogni volta che si apre, con i pixel
del monitor su cui si apre (compilato da `sketchybarrc`, non è nel repo).

Quando uno dei pacchetti del `Brewfile` ha una nuova versione su Homebrew, all'estrema destra
compare un pallino rosso con quanti sono. Un clic apre l'elenco con la versione installata e quella
nuova (`1.8.4 → 1.9.0`), un clic su un pacchetto lo aggiorna e, se sono più di uno, c'è anche
*Aggiorna tutto*, che aggiorna solo quelli dell'elenco: gli altri pacchetti di Homebrew restano
com'erano, tranne le dipendenze di cui una nuova versione ha bisogno. Durante l'aggiornamento il
pallino diventa giallo e gli altri clic vengono ignorati. `plugins/brew.sh` esegue `brew update`
ogni ora, al risveglio e a ogni `sketchybar --reload`. Dopo l'aggiornamento riavvia `sketchybar` e
`borders` con i loro comandi di `after-startup-command` in `aerospace.toml`, così usano subito la
nuova versione. Se un aggiornamento non riesce compare una notifica, e un clic apre l'output di brew
(`~/Library/Logs/sketchybar-brew.log`). `font-sf-pro` ha versione `latest`, quindi Homebrew non lo
segnala mai come da aggiornare.

AeroSpace invece continua con la vecchia versione finché non si riavvia, e riavviarlo da solo in
mezzo al lavoro rimescolerebbe le finestre. Dopo averlo aggiornato compare una notifica: un clic
apre l'elenco, che in cima ha *Riavvia AeroSpace*, e il pallino la conta finché non lo riavvii. La
riga c'è anche se hai aggiornato AeroSpace da terminale, perché `aerospace --version` mostra sia la
versione installata sia quella in esecuzione. Il riavvio disattiva AeroSpace, che così rimette sullo
schermo le finestre dei workspace nascosti, poi lo chiude e lo riapre: ogni finestra finisce nel
workspace visibile sul suo monitor, tranne le app con una regola `on-window-detected`, che tornano
nel loro. Le notifiche le manda `terminal-notifier`: alla prima macOS chiede il permesso, scegli
*Consenti*.

La scintilla arancione di Claude mostra quanto hai usato dei limiti del tuo piano, la sessione di
5 ore e la settimana (`50% · 39%`), in giallo dal 75% e in rosso dal 90%. Un clic apre il nome,
l'email e il piano dell'account e, per ciascun limite, la percentuale, una barra e quanto manca al
reset (`Reset tra 2 h 57 min · 01:10`). In fondo c'è *Esci*, che vuole un secondo clic prima di
scollegare l'account. Senza un account c'è solo *Accedi*: apre la pagina di accesso di Claude nel
browser e, finito l'accesso, l'elemento si aggiorna; se non riesce compare una notifica, e un clic
apre l'output di claude (`~/Library/Logs/sketchybar-claude.log`). I numeri sono quelli di `/usage`
di Claude Code: `plugins/claude.sh` li chiede a `claude -p` senza mandare messaggi, quindi senza
consumare crediti, ogni 5 minuti, al risveglio e a ogni clic (in alto a destra compare
*Aggiornamento…* finché non arrivano), e Claude Code rinnova da solo il login scaduto. Claude Code
chiede i numeri al server solo se quelli che ha sono più vecchi di un minuto. Se una lettura non riesce, per esempio senza rete, restano gli ultimi numeri in
grigio fino alla successiva. Serve [Claude Code](https://code.claude.com/docs) (lo cerca anche fuori dal
`PATH`: `~/.local/bin`, Homebrew, nvm) e `jq`, che macOS ha da Sequoia. L'icona è quella della
barra dei menu dell'app Claude, che `helpers/claude_icon.js` colora in `helpers/claude_icon.png`
(non è nel repo); senza l'app al suo posto c'è ✻.

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
