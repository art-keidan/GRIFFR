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

## Terza tappa: rientri tratteggiati, aggiornamento dal vivo esplicito

- I rientri sinistro e destro hanno il tratteggio, fra il bordo della colonna e la guida, come gli spazi prima e dopo.
- La portata non era riconoscibile (due icone): ora sta nel riquadro in alto a destra, a parole, «Changes to: All
  “Body” | This paragraph». Accanto, l'interruttore **Live on all** (occhio): spento, l'anteprima cambia solo il
  capoverso evidenziato, gli altri restano com'erano finché non si salva; Save mette comunque le modifiche nello stile.
- La build con la progettazione è anche in `GRIFFR-fork-stili/build/GRIFFR Stili.app`; quella di `main` che c'era è
  nel Cestino.
- Prova nuova: `livePreviewOff`. 220 prove di WordProcessorTests verdi. Verifica a schermo di questa tappa non fatta:
  l'app era aperta dall'utente con la build precedente.

## Quarta tappa: un solo controllo per «dal vivo», tenuta con n righe dei vicini (formato 17)

- **Difetto di «Live on all»**: il meccanismo funzionava; l'interfaccia aveva due controlli sovrapposti («Changes to:
  All / This paragraph» e «Live on all»), e con «This paragraph» scelto l'occhio non aveva effetto. Ora c'è un solo
  gruppo di tre icone nella barra, accanto al nome dello stile: **occhio** (tutti i capoversi dello stile, dal vivo;
  Save nello stile), **occhio barrato** (nello stile, ma dal vivo solo questo capoverso), **¶** (solo questo capoverso,
  come valori dati a mano). Il riquadro in alto a destra è ridotto a puntino (modifiche non salvate) · Cancel · Save.
- **Tieni con n righe del seguente**: tondino con il numero nel margine destro, sotto il capoverso; si tira in giù
  dentro il seguente, scatta di riga in riga, le righe tenute si colorano con una graffa; a 0 la tenuta si spegne.
- **Tieni con n righe del precedente** (nuovo): lo stesso sopra il capoverso, tirato in su dentro il precedente.
- **Formato 17** (`DocumentFormat.version = 17`): `keep-next-lines` e `keep-with-previous` su `style` e `p`, proprietà
  di formula `nextLines` e `previousLines`. Si scrive 17 solo se un documento li usa; i file vecchi restano leggibili.
- **Impaginazione** (`PageLayout`): con «tieni col seguente» e n righe, il seguente deve avere almeno n righe in fondo
  alla pagina, altrimenti passa con il precedente (riusa la catena di «tieni col seguente»). Con «tieni con n righe del
  precedente», il precedente entra nella catena; se nella pagina in cui comincia questo ci sono meno di n sue righe, si
  rifà spezzandolo perché le sue ultime n righe passino qui (se si spezzerebbe troppo presto, passa tutto).
- Prove nuove: `KeepLinesTests` (motore: seguente, precedente, precedente già spezzato, lettura e scrittura) e in
  `ParagraphDesignTests` i trascinatori della tenuta e Live riacceso. `LineKeepingInspectorTests` ora conta sei voci.
- Verifica a schermo: tre icone e riquadro minimo; occhio acceso con tutti i «Body» aggiornati; «Keep with 2 lines of
  the next»; «solo questo capoverso» con «Keep with 4 lines of the previous» (il precedente passa intero nella pagina);
  Annulla dentro la bozza. Da sapere: con l'occhio acceso la tenuta vale per tutti i capoversi dello stile, e numeri alti
  creano catene lunghe e pagine con buchi. Limite visto: la barra dei pulsanti, sopra il capoverso, copre le righe del
  precedente che si agganciano.

## La testata nel designer (8 novembre 2026)

- Motore: la pagina composta registra dove sono posate le parti della testata (`LaidOutPage.headingParts`, con il posto
  della parte in `HeadingComposition.parts`): la fascia di etichetta, numero, risultato e spazio, il filetto vero, il
  riquadro del numero accanto al titolo. Il formato non cambia. Le operazioni sulle parti (aggiungi, cambia, sposta,
  togli) sono ora funzioni di `HeadingComposition`, usate dal compositore e dal designer.
- Bozza: `headings` per stile; Salva la scrive nello stile in un passo di Annulla, Cancel la scarta. Se lo stile
  ereditava la testata, ne prende una copia sua.
- Pagina: cornici tratteggiate per tutte le parti; un clic su una fascia sceglie la parte (cornice piena con il nome);
  solo la parte scelta ha le maniglie, nel margine destro: altezza minima (etichetta, numero, risultato), altezza dello
  spazio, lunghezza e spessore del filetto, distanza del numero accanto al titolo; al mezzo millimetro, valore in mm.
- Barra: icona «testata» con il menu delle parti (pronta, etichetta, numero, numero accanto, risultato, filetto, spazio,
  scelta di una parte, togli la testata); con una parte scelta, una seconda riga: testo (Invio applica), allineamento o
  lato, stile, su, giù, togli, chiudi.
- Si cambia solo nello stile con l'occhio pieno; con l'occhio barrato o ¶ i comandi sono spenti. Con l'occhio barrato
  la testata della bozza si vede comunque su tutti i titoli (vive solo nello stile).
- Non ancora: la parte «titolo» (allineamento e altezza minima propri) non ha maniglie; il lato del numero accanto si
  cambia dalla barra, non trascinandolo.

## Filetti liberi (formato 18) e fascia della progettazione (8 novembre 2026)

- **Modello** (`Sources/Typesetting/ParagraphRules.swift`): un filetto ha un aggancio (sopra, sotto, sinistra, destra
  del capoverso), uno scarto verso l'esterno dal bordo agganciato, un prolungamento all'inizio e alla fine (negativo
  accorcia), uno spessore. Quanti se ne vuole. Stanno nello stile di paragrafo (`StyleValues.rules`, si ereditano) o sul
  singolo capoverso (attributo `.paragraphRules`, sostituisce quelli dello stile). Non occupano spazio.
- **Formato 18**: attributo `rules="top 3 0 0 0.5; left 6 0 0 1"` su `style` e `p`; si scrive 18 solo se usati.
- **Impaginazione**: posati dopo il capoverso: sopra sulla prima pagina, sotto sull'ultima, ai lati su ogni pagina lungo
  le righe (anche in una cella, rispetto alla cella). Disegnati con gli altri filetti della pagina; `LaidOutPage.paragraphRules`
  dice dove sono, per la progettazione.
- **Progettazione**: menu «filetti» nella barra (aggiungi sopra, sotto, a sinistra, a destra; scegli); un clic su un
  filetto lo sceglie; il filetto scelto ha tre maniglie (il corpo lo allontana o lo avvicina al testo, i due capi lo
  allungano), al mezzo punto, valore in mm; riga della barra con aggancio, spessore, togli. Bozza, occhio e ¶ come il resto.
- **Fascia della progettazione**: la barra non sta più sopra le pagine (copriva il testo): è una fascia fra il righello e
  le pagine, che compare solo in Design, con i pulsanti a sinistra (vanno a capo se la fascia è stretta) e Annulla/Salva a destra.
- Verifica a schermo: filetto a sinistra aggiunto e spostato («Left, 10,1 mm from the text»), visibile su tutti i
  «Body»; filetto sotto aggiunto e allungato («End 9,9 mm»); fascia sotto il righello. Limiti: sul capoverso progettato le
  maniglie del filetto a sinistra stanno vicine a quelle del rientro e degli spazi; l'etichetta del valore può coprire il testo.

## Filetti: limiti, Maiuscole, attrazione (8 novembre 2026)

- **Limiti verso il testo**: il filetto sopra non scende sotto l'alto della prima riga, quello sotto non sale sopra il
  basso dell'ultima, quelli ai lati non entrano oltre il bordo del testo (il rientro). Lontano dal testo sono liberi.
- **Con Maiuscole** (sul corpo del filetto) il filetto trascina il suo spazio: segue il mouse e lo spazio dal suo lato
  cambia della stessa misura. Sopra → spazio prima (in giù cresce, il capoverso scende con il filetto); sotto → spazio
  dopo (in giù cresce, il testo che segue scende); sinistra/destra → rientro (verso il centro cresce, il testo si
  stringe). A zero lo spazio si ferma e il filetto prosegue da solo verso l'esterno. Filetto e spazio vanno nella bozza
  in un solo passo.
- **Attrazione**: durante il gesto la maniglia è attirata (entro 4 pixel) da bordi del testo e della colonna, guide dei
  rientri, linee di base della prima e dell'ultima riga, bordi degli spazi prima e dopo, metà dello spazio verso i
  capoversi vicini, metà dei margini, gli altri filetti del capoverso; una guida tratteggiata attraversa la pagina. ⌘
  la spegne. Non fatta: l'attrazione debole ai millimetri interi.
- Prova: `rulesPushSpace`. Verifica a schermo: filetto sotto aggiunto e trascinato; lo spostamento con Maiuscole non si
  è potuto provare a schermo (lo strumento non tiene premuto Maiuscole durante il trascinamento).
