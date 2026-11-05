# Compositore di stili ad azioni · resoconto

6 novembre 2026. Realizza la direzione approvata nel [prototipo](Interfaccia-formule/prototipo-automator.html) secondo la [consegna](CONSEGNA-CLAUDE.md).

## Che cosa c'è nell'app

Formato › Compositore di stili… apre una finestra con quattro viste: Stili, Selezioni, Regole, Formule. Le ultime tre restano quelle di prima; la vista Stili è il compositore nuovo, in tre aree ridimensionabili.

- **Libreria, a sinistra.** Il menu dello stile, la ricerca, e i gruppi Formattazione, Comportamenti, Condizioni dell'azione scelta, Calcoli, Formule del documento. Ogni voce aggiunge un'azione o una variabile con un clic; offre solo le proprietà ammesse per il tipo dello stile. Le condizioni si danno all'azione scelta, non a quelle che seguono; una condizione non ammessa (per esempio «primo della pagina» su «stile dopo Invio») non si applica e la barra di stato dice perché.
- **Flusso, al centro.** Lo stile, «Eredita da», l'oggetto iniziale; poi le variabili e le azioni, raggruppate per fase nell'ordine in cui il motore le valuta. Ogni azione è una sola superficie: numero, apri/richiudi, simbolo, titolo, e richiusa una riga che dice cosa fa («a 12 pt · se primo della pagina»). Aperta mostra operazione e proprietà, il valore su una riga sua, condizione e destinatario, e l'ingresso → risultato sul campione. ↑ ↓ spostano l'azione dentro la sua fase e si spengono al confine (il suggerimento lo dice); con l'azione scelta valgono ⌥⌘↑ e ⌥⌘↓. × la toglie.
- **Anteprima, a destra.** Testo di prova, carattere di partenza, contesto (primo della pagina, inizio sequenza, paragrafo precedente, misure naturali quando servono), il campione composto con rientro e spazio prima, i valori delle proprietà toccate, lo stato o la diagnosi, Ricarica e Applica al documento (⌘↩). Prova rivaluta il campione.

## Variabili nominate

Una variabile è un risultato con un nome dentro lo stile: «Distanza» = Rientro con margine(Base 12 pt). Le azioni dello stesso stile la richiamano per identità (ƒ(x) accanto al valore), anche più di una; il nome si cambia senza interrompere nulla. Una variabile può usarne un'altra; un giro, una variabile assente o due nomi uguali sono diagnosi. Una variabile usata non si toglie. «Dai un nome a questo calcolo» trasforma il calcolo scritto in un'azione in una variabile; «Valore fisso» riporta l'azione al valore che la variabile dava.

Le formule del documento compaiono come una sola azione «Richiama · nome» con gli argomenti, uno per riga; «Apri la definizione» porta alla vista Formule.

## Modello e formato

Le variabili sono nel modello degli stili (`StyleVariable`, `NamedStyle.variables`, il caso `FormulaExpression.variable`): non c'è un secondo modello per la finestra. Prima di valutare, le variabili si sostituiscono con le loro espressioni; il resto della risoluzione (formule riutilizzabili, fasi, regole contestuali) è quello di prima.

Il formato passa alla versione 12 solo per i documenti con variabili: `<variable id name expression/>` dentro `style`, prima delle formule. I file fino alla 11 si leggono come prima; una versione precedente rifiuta un file 12. Incollare o importare uno stile porta con sé le formule del documento richiamate dalle sue variabili, con le identità rinnovate nei conflitti.

## Prove

- `StyleVariableTests`: Distanza 18 pt su due proprietà, 22 pt con margine 10; rinomina e catene; diagnosi; andata e ritorno nel file e rifiuto della versione 11; importazione.
- `ActionComposerTests`: dal compositore, Base 12 + margine 6 → Distanza → rientro sinistro, 18 pt nel testo; margine 10 → 22 pt su tutte le occorrenze; Annulla, Ripeti, file; ritorno al valore fisso; variabile usata, fasi, condizione non ammessa, condizione per una sola azione; finestra a 740, 1000 e 1400 punti senza allargarsi.
- Le prove complete passano: 210 nell'app, 489 nel motore (1 problema noto, preesistente).

## Verifica visiva e limiti

Visto nell'app compilata, in sottofondo: le tre aree, la libreria con la ricerca, l'aggiunta di azioni e di variabili, l'apertura dei blocchi, il campione di `prova-formule-riutilizzabili.grx` con rientro 18 pt e l'azione collegata «Rientro con margine(Base: 12 pt)». A schermo ho corretto: menu che si allargavano a tutta la riga, flusso più largo della sua colonna, argomenti schiacciati, gruppi vuoti nella ricerca, allineamenti in inglese.

Non verificato a schermo: l'apertura dei menu (ƒ(x), proprietà, stile) e la scrittura nei campi della finestra, che l'automazione in sottofondo non raggiunge; il modo scuro del compositore; VoiceOver (le etichette ci sono, non l'ho ascoltato). Non c'è il trascinamento delle azioni: si spostano con i pulsanti e con la tastiera.
