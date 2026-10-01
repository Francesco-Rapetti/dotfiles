# dotfiles

## Screenshot dei plugin di SketchyBar

Ogni volta che aggiungi o modifichi un plugin di SketchyBar (`sketchybar/plugins/*.sh`, i suoi
elementi in `sketchybarrc`, il suo helper o qualcosa che cambia com'è disegnato, come
`colors.sh`), aggiorna anche i suoi screenshot nel README, con dati inventati:

1. Se il plugin legge dati nuovi, aggiungili finti: un comando in `screenshots/mock/bin`, un helper in
   `screenshots/mock/helpers` (gli helper veri non devono mai partire: cambierebbero il Mac, la casa,
   l'account) o le variabili dell'evento in `screenshots/take.sh`. Mai dati veri: niente nomi, email,
   dispositivi, reti o eventi reali.
2. Per un plugin nuovo aggiungi una funzione `shot_<nome>` in `take.sh`, mettila in `SHOTS` e, se
   sta nella barra, il suo elemento in `LEFT` o `RIGHT`, poi la sua esecuzione in `mock_bar`.
3. Rifai solo le immagini toccate, più `bar` se cambia la barra: `screenshots/take.sh <nome> bar`.
   La barra mostra i dati finti per qualche secondo, poi `sketchybar --reload` la ripristina.
4. Guarda i PNG prima di usarli (che il popup sia intero e senza dati veri), poi mettili nel
   README come `![…](screenshots/<nome>.png)` subito prima del paragrafo che descrive il plugin.

Se una modifica non cambia niente di visibile (un commento, un refactoring) non servono screenshot
nuovi.
