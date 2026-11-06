# Stato del progetto e lavoro residuo

Aggiornato il 6 novembre 2026.

## Interfaccia in inglese · 6 novembre

Per la diffusione pubblica l'interfaccia è in inglese: menu, fasce e zone, ispettore, schede, compositore, avvisi, messaggi d'errore del formato e diagnosi del motore. L'app dichiara l'inglese come lingua (`CFBundleDevelopmentRegion`), così anche i pannelli di sistema e i nomi degli assi dei font restano in inglese su un Mac in italiano. Le disposizioni delle fasce salvate in italiano passano ai nomi inglesi al caricamento.

I documenti nuovi usano nomi predefiniti inglesi (Body, Heading 1…, Notes, Figures, Footnote, Default, ruolo «chapter») e Lorem è in inglese. I documenti di prima tengono i loro nomi; «Nota a piè di pagina» e «Predefinito» diventano Footnote e Default alla lettura (`LegacyNamesTests`). Nella bacheca ogni menu mostra una sola freccia, quella della pastiglia.

## Compositore ad azioni · realizzato

Il compositore ispirato ad Automator è nell'app: libreria, flusso per fase con blocchi richiudibili, variabili nominate salvate nello stile (formato 12), anteprima con Applica. Il [resoconto](COMPOSITORE-AD-AZIONI.md) dice che cosa c'è, come è provato e che cosa non è stato verificato a schermo. Le tappe sotto riprendono da qui.

## Che cosa è stato realizzato

Il fork contiene già il primo nucleo del modello a oggetti per gli stili:

- gli stili di paragrafo, parola e carattere hanno una struttura interna a formule;
- `Imposta`, `Aggiungi` e `Sottrai` sono operazioni distinte, con effetti corretti sui tratti del font e sulle misure;
- formule, eredità, condizioni, contesto, destinatari e comportamenti sono valutati dal modello comune;
- la bacheca visuale e i controlli ordinari modificano la stessa definizione, con anteprima, provenienza, Annulla e Ripeti;
- sono disponibili le prime condizioni e azioni contestuali: primo della pagina, distanza d'apertura, tenuta delle righe, apertura di sezione, livello del titolo e stile dopo Invio;
- `Carattere` è già rappresentato nel modello come elemento interrogabile; i campi tradizionali di pagina e sezione continuano a funzionare;
- il primo campo formula persistente è disponibile: `Posizione → Pagina contenente → Numero → Scrivi risultato qui`, salvato come formula distinta dai campi storici;
- il formato conserva le nuove definizioni e mantiene la lettura dei documenti precedenti;
- la barra del percorso della finestra principale è stata resa scorrevole, così l'inserimento ripetuto di Lorem non allarga più la finestra senza limite;
- la procedura di compilazione lascia una sola applicazione corrente, `build/GRIFFR Stili.app`.

Le tappe archiviate in `Appunti/archivio/` sono documentazione storica delle decisioni e delle verifiche già eseguite. Non sono più il piano di lavoro corrente.

## Che cosa manca per completare il sogno delle formule

### 1. Formule riutilizzabili e compositore completo

Il primo percorso completo è implementato: definizioni nominate con parametri tipizzati, somme, chiamate, argomenti di prova e risultati numerici, lunghezze e booleani. La bacheca costruisce le espressioni e le collega alle proprietà compatibili degli stili; il testo, l'ispettore, Annulla, il file e l'importazione condividono la definizione. Il formato 11 conserva i collegamenti; il 12 aggiunge le variabili degli stili. Le diagnosi coprono riferimenti e parametri mancanti, tipi, cicli e limiti di espansione.

Il [resoconto e il campione](FORMULE-RIUTILIZZABILI.md) descrivono il percorso utilizzabile. L'estensione verso il catalogo completo comprende ancora operazioni sugli oggetti editoriali, risultati facoltativi e ulteriori effetti.

### 2. `Posizione`, campi e `Scrivi risultato` · realizzato il 6 novembre

Tutti i campi sono formule, con un oggetto di partenza, un risultato e il punto in cui si scrive:

- `Posizione → Pagina contenente → Numero` (formato 9);
- `Documento → Numero delle pagine`, `Posizione → Sezione contenente (ruolo) → Titolo` e `… → Numero` (formato 13).

Per scelta dell'autore i campi storici (`page`, `pages`, `section-title`, `section-number`) si leggono ancora e diventano le formule equivalenti; il file scrive soltanto formule. Un documento di prima che contiene campi, dopo l'apertura, si salva quindi in una copia nel formato nuovo (la protezione dell'originale del fork resta). Inserisci › Campo inserisce le formule con i nomi di sempre; il suggerimento di ogni voce ne dice la catena. Il campo è un carattere solo con la sua formula e lo stile del tratto: si aggiorna a ogni composizione e non si duplica salvando, riaprendo o ricomponendo (`FieldFormulaTests`).

Rimandato alla tappa 3: «Scrivi risultato» come azione del compositore, cioè uno stile che genera testo, che è il centro delle testate. Restano da aggiungere risultati come la pagina della sezione e i rimandi a un paragrafo.

### 3. Testate di capitolo nello spirito di `memoir` · primo nucleo realizzato il 6 novembre

Uno stile di paragrafo può avere una testata (`HeadingComposition`, formato 14): una sequenza verticale di parti, cioè etichetta («Capitolo»), numero della sezione, titolo, filetto e spazio. Ogni parte di testo ha uno stile, un allineamento (anche lato esterno o interno sulle pagine affacciate) e un'altezza minima. Il titolo resta il solo paragrafo del documento; le altre parti si compongono come i segni degli elenchi e i filetti e si posano con lui, contando per il salto pagina, la tenuta e la distanza a inizio pagina. Il numero compare una volta: con una parte «numero» il segno della Lista del titolo non si disegna. La distanza d'apertura vale per il bordo superiore della testata intera. Gli stili derivati ereditano la testata.

Il caso guida è provato (`HeadingCompositionTests`): 12 + 3 + 0,5 + 2,5 mm sopra e 8 mm sotto spostano il corpo di 26 mm; un titolo di tre righe lo abbassa quanto le due righe in più; il numero sta a destra sulle dispari e a sinistra sulle pari; con 30 mm di apertura il filetto cade a 45 mm. Nel compositore: la «Testata pronta», le singole parti, il blocco con le parti in ordine e l'anteprima della sequenza.

Completato il 6 novembre (formato 15):

- **Numero accanto al titolo** (`numberBeside`): sulla prima riga del titolo, a sinistra, a destra, all'esterno o all'interno, a una distanza scelta; le righe del titolo si scostano della larghezza del numero più la distanza (al massimo metà della misura).
- **Sezioni senza numero**: le parti «numero» e «numero accanto» spariscono con la loro fascia, e il titolo torna a tutta la misura. L'etichetta («Chapter») resta: farla sparire insieme al numero sarebbe una scelta in più.
- **La parte «titolo»** può avere un allineamento proprio (anche esterno o interno) e un'altezza minima, in cui il titolo poggia sul fondo.

Nel compositore ci sono la voce «Number beside title» e, nella riga del titolo, l'allineamento e l'altezza. Una testata che non usa le novità si scrive ancora in formato 14. Le prove sono in `HeadingCompositionTests` (che ora gira una prova alla volta, come le altre suite che creano font) e in `ActionComposerTests`. Un PDF di prova con le quattro varianti è stato guardato; il compositore nell'app non ancora.

### 4. Flottanti derivati e relazioni fra oggetti

Manca il caso completo «trova la quinta parola e crea una nota marginale a 1 cm dal bordo». Occorre:

- mantenere l'identità del proprietario e del contenuto scritto dall'autore;
- conservare il flottante attraverso salvataggio, incolla, divisione e fusione dei capoversi;
- collocarlo rispetto al bordo fisico della pagina, segnalando le collisioni;
- rivalutare il bersaglio quando il testo cambia, senza creare copie della nota.

Nello stesso gruppo rientrano le relazioni generali fra un paragrafo e i suoi vicini, oltre alle azioni già disponibili dopo Invio.

### 5. Tabelle, flottanti esistenti e migrazione completa

Gli stili di tabella, cella e flottante hanno ancora percorsi specifici. Vanno portati nella struttura comune delle formule mantenendo griglia, filetti, note, figure, numerazione, eccezioni locali e compatibilità con i documenti già scritti. La conversione deve coprire anche stili personalizzati e proprietà esplicitamente disattivate tramite `Sottrai`.

### 6. Verifica dell'interfaccia reale

Restano da provare direttamente nell'app, oltre alle prove automatiche:

- il compositore visuale con formule lunghe, risultati mancanti e diagnosi;
- campi, testate, flottanti marginali, schede Liste e Pagine;
- tabelle, pagine miste, tenuta delle righe e trascinamento nella mappa;
- tastiera, VoiceOver, contrasto e dimensioni dei controlli.

## Lavoro tipografico indipendente

Dopo il nucleo delle formule restano anche miglioramenti del motore, da affrontare separatamente: tabulazioni nel compositore ottimale, griglia delle linee di base, spaziatura delle lettere nella giustificazione, composizione ottimale da destra a sinistra, regole tipografiche per lingua, ottimizzazione considerando la pagina intera, colonne e indice generato.

## Ordine consigliato

1. Completato il primo vocabolario di formule nominate, parametri, tipi e diagnosi nel compositore; estendere le operazioni insieme ai casi successivi.
2. ~~Implementare `Posizione` e `Scrivi risultato` come campi persistenti.~~ Fatto (formato 13).
3. ~~Testata di capitolo.~~ Fatto (formati 14 e 15).
4. Realizzare il flottante derivato della quinta parola e generalizzare le relazioni fra oggetti.
5. Migrare tabelle e flottanti nella stessa grammatica e chiudere la compatibilità dei documenti.
6. Fare la verifica d'uso completa nell'app e solo dopo riprendere le estensioni tipografiche indipendenti.

Il primo incremento concreto sui campi è implementato. Il passo successivo in quest'area è estendere la grammatica a risultati e operazioni ulteriori, mantenendo l'ancoraggio, la ricomposizione, il salvataggio e l'aggiornamento senza duplicare i campi.
