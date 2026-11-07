# Progettare il capoverso sulla pagina

Fork `claude/compositore-paragrafo-d1eb7e`, dal commit `1784d7f` di `main`. Esperimento: al posto dell'ispettore a righe,
il capoverso si progetta trascinando le sue misure direttamente sulla pagina.

## Che cosa è cambiato

- **Ispettore della vista «Selection» tolto.** Niente righe, pallini, gruppi, filtro All/Set, percorso; tolta anche la
  fascia del percorso sopra la pagina. La vista Selection ora ha solo il pulsante «Design the Paragraph» e una spiegazione.
  La vista Definitions (Styles, Lists, Floats, Rules, Pages, Tables) è invariata: la scheda Styles usa ancora
  `InspectorView(rowsOnly: true)`, che resta in `InspectorPanel.swift`.
- **Il motore non cambia.** `TextStyling.inspect`, `withRuleSources`, `RuleInfluence`, `StyleSheet.setting` restano.
- **Comandi senza interfaccia, per ora.** Sezioni (ruolo, comincia, tipi di pagina, numeri), tabelle (stile, aspetto,
  intestazione), celle, tipo della pagina del cursore: i comandi restano nel controller
  (`EditorWindowController+Selezione.swift`) e nelle prove, ma i loro moduli non si vedono più. Andranno rifatti nel
  modo nuovo. Anche «Crea uno stile da qui…» (dall'ispettore) è tolto; «Crea una regola da qui…» resta come funzione.

## La modalità

- Si entra e si esce con il pulsante **Design** nella fascia del paragrafo (zona «design»), con Vista › Design Paragraph
  (⌥⌘G), o dal pannello Selection. Esc esce.
- Il capoverso del cursore resta nitido; il resto della pagina è velato di bianco (attenuato, non sfocato). Cliccando
  in un altro capoverso la progettazione passa a quello.
- Maniglie sulla pagina (`PagesView+Progetta.swift`): rientro sinistro e destro (barrette sulle guide), prima riga
  (triangolo sopra la prima riga), spazio prima e dopo (barrette sul bordo delle fasce tratteggiate), distanza fra le
  righe (barretta nel margine destro, fra la prima e la seconda riga; cambia `lineSpacing`). Durante il trascinamento si
  vede il valore («Left indent 18 pt») e le pagine si ricompongono dal vivo (anteprima su una copia del testo, con lo
  stile cambiato); il documento cambia solo al rilascio. Passo di 1 pt, con ⌥ di 0,1 pt.
- Pulsanti sopra il capoverso (`ParagraphDesignBar.swift`): nome dello stile, allineamento, altezza di riga, menu
  «Pages» (tieni le righe insieme, tieni con il seguente, righe in fondo e in cima, distanza d'apertura), menu «More»
  (lista, sillabazione, lingua, stile dopo Invio, font, corpo), «Done».
- **Ogni modifica va nello stile del paragrafo**, un passo di Annulla per gesto o pulsante («Style “Body”: left indent»).
  Se il capoverso aveva quel valore dato a mano, lo perde nello stesso passo, così si vede quello dello stile.
- Una misura calcolata da una formula dello stile è bloccata: maniglia grigia con «ƒ»; un clic apre lo stile nel
  compositore. Nel menu, la voce apre il compositore invece di cambiare il valore.

## Prove

`Tests/WordProcessorTests/ParagraphDesignTests.swift`: entrata/uscita e capoverso seguito, ogni maniglia nello stile
con Annulla/Ripeti, anteprima senza toccare il documento e valore a mano tolto, formula bloccata, pulsanti nello stile.

Prove tolte perché provavano solo l'interfaccia dell'ispettore: espansione dei glifi trascinata (I), proprietà
dinamiche (I1b), altezza delle pagine scegliendo nel percorso (I2), Tab fra i campi dell'ispettore, «Crea uno stile da
qui» (R2), formula contestuale vista nell'ispettore (ContextStyleEditorTests), ispettore del testo con le formule
(FormulaControlTests), percorso delle sezioni annidate (WindowHousekeepingTests, parte finale). Le altre sono adattate ai
comandi del controller.

## Limiti e idee dopo

- Velatura invece di sfocatura vera; testo vero, non lettere indistinte.
- Le maniglie lavorano sui valori di paragrafo dello stile; gli elenchi (rientri della Lista) restano al righello.
- Più colonne, celle di tabella e note: le guide usano la colonna (o la cella) della riga; non provato a fondo.

Prova B1 (barra di stato): ora passa da sola all'interfaccia dettagliata; prima contava sulla prova I2, tolta, che la
lasciava accesa. Risultato: tutte le 215 prove di WordProcessorTests verdi, e le suite indicate in CLAUDE.md.
La vista Selection non comunica le sue misure alla finestra (`sizingOptions = []`), come il vecchio contenitore
dell'ispettore: altrimenti la finestra cambiava dimensione (prove ViewState e Z1).

Verifica a schermo: non fatta (accesso all'app non concesso in questa sessione).

## Verifica a schermo (7 novembre 2026)

Vista nell'app ricompilata, su un documento Lorem: entrata con «Design»; titolo e capoverso «Body» nitidi con il resto
velato; rientro sinistro trascinato (tutti i «Body» seguono, righello aggiornato), Annulla in un passo; allineamento al
centro dalla barra; spazio dopo trascinato a 32 pt con la fascia tratteggiata; Esc esce. Corretto dopo la prima occhiata:
le maniglie degli spazi stavano sopra il testo (ora nel margine sinistro) e le lettere nei margini ottici restavano
velate. Non visti: l'etichetta del valore durante il trascinamento (lo strumento non cattura a metà gesto), i menu
«Pages» e «More» aperti, la maniglia ƒ bloccata, il tema scuro.

## Seconda tappa (7 novembre 2026): bozza, portata, margini, interlinea, icone

Richieste dell'utente: pulsanti Salva e Annulla; un pulsante per aggiornare dal vivo tutti i capoversi dello stile o
solo quello evidenziato; margini della pagina disegnati e trascinabili; più proprietà come icone; interlinea presa a
mano sulle linee sotto le lettere.

- **Bozza.** I gesti e i pulsanti non scrivono più nel documento: vanno in una bozza (`ParagraphDesignDraft`) che le
  pagine mostrano dal vivo, ricomponendo una copia del testo. **Save** (riquadro fisso in alto a destra della zona
  visibile, o di nuovo il pulsante Design) scrive tutto in un passo di Annulla «Paragraph Design»; **Cancel** o Esc la
  scartano. Durante la progettazione Annulla/Ripeti (menu e barra) tolgono e rimettono i passi della bozza.
- **Portata.** In testa alla barra: «Body» (dal vivo su tutti i capoversi dello stile, poi nello stile) o ¶ (solo
  questo capoverso, come valori dati a mano; lo stile non cambia). Nella portata del capoverso le misure calcolate da una
  formula non sono bloccate. Interpretazione mia della richiesta: è la portata della modifica, non solo dell'anteprima.
- **Margini.** Lo specchio di ogni pagina è tratteggiato, con una maniglia a metà di ogni lato. Il trascinamento cambia
  il formato del tipo di pagina di quella pagina (o quello predefinito), al mezzo millimetro (⌥ al punto); con le pagine
  affacciate, sulle pagine pari i lati interno ed esterno si scambiano. Il valore si legge in mm.
- **Interlinea.** Sotto ogni riga del capoverso c'è la sua linea di base. Si prende una linea dalla seconda in giù: la
  si sposta di n punti, e la distanza fra le righe cambia di n diviso il numero di righe che la separano dalla prima.
  Tolta la vecchia maniglia nel margine destro.
- **Icone.** Allineamento, altezza di riga, tieni insieme, tieni con il seguente, righe in fondo e in cima (con il
  numero), distanza d'apertura, lista, sillabazione, lingua, stile dopo Invio, font, corpo: ciascuno un'icona con la
  spiegazione al passaggio del mouse; un piccolo «ƒ» segna quelle calcolate da una formula.

Verifica a schermo: entrata, portata «solo questo capoverso», linea di base trascinata (le righe di tutti i «Body» si
allargano), margine inferiore trascinato (il capoverso passa alla pagina dopo), Save e un Annulla che toglie tutto,
Cancel che scarta. Correzione dopo l'occhiata: la barra era più larga della zona visibile, ora Salva/Annulla stanno a
parte. Non visti: i menu aperti, l'etichetta del valore durante il gesto, il tema scuro.

Prove: `ParagraphDesignTests` (9) rifatte per la bozza: Salva in un passo, Cancel, Annulla interno, solo questo
capoverso, valore a mano, formula, pulsanti, margini, lati con le pagine affacciate.
