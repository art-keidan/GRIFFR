# Stato del progetto e lavoro residuo

Aggiornato il 5 novembre 2026.

## Priorità attuale · revamp con Claude

L’utente ha scelto il compositore ad azioni ispirato ad Automator. Prima delle tappe funzionali residue va realizzata questa interfaccia nativa. Prototipo, scelte, punti del codice e criteri di completamento sono nella [consegna a Claude](CONSEGNA-CLAUDE.md). Le tappe elencate sotto restano conservate e riprendono dopo il revamp.

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

Il primo percorso completo è implementato: definizioni nominate con parametri tipizzati, somme, chiamate, argomenti di prova e risultati numerici, lunghezze e booleani. La bacheca costruisce le espressioni e le collega alle proprietà compatibili degli stili; il testo, l'ispettore, Annulla, il file e l'importazione condividono la definizione. Il formato 11 conserva i collegamenti. Le diagnosi coprono riferimenti e parametri mancanti, tipi, cicli e limiti di espansione.

Il [resoconto e il campione](FORMULE-RIUTILIZZABILI.md) descrivono il percorso utilizzabile. L'estensione verso il catalogo completo comprende ancora operazioni sugli oggetti editoriali, risultati facoltativi e ulteriori effetti.

### 2. `Posizione`, campi e `Scrivi risultato`

Il motore ha già campi fissi per numero di pagina, totale delle pagine e sezione corrente. È stato aggiunto il primo campo formula dinamico:

`Posizione → Pagina contenente → Numero formattato → Scrivi risultato qui`.

Il campo dovrà conservare il punto a cui è ancorato, la formula e lo stile del testo prodotto; dovrà aggiornarsi quando cambia la paginazione, senza duplicarsi dopo salvataggio, riapertura o ricomposizione.

### 3. Testate di capitolo nello spirito di `memoir`

Va introdotta una composizione associata allo stile del titolo, con parti ordinate come numero, filetto, spaziatura e titolo. Servono riferimenti al numero e al titolo della sezione, stili per le singole parti, pagine pari/dispari e aggiornamento quando il titolo cambia altezza o posizione.

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
2. Implementare `Posizione` e `Scrivi risultato` come campi persistenti.
3. Realizzare una testata di capitolo completa.
4. Realizzare il flottante derivato della quinta parola e generalizzare le relazioni fra oggetti.
5. Migrare tabelle e flottanti nella stessa grammatica e chiudere la compatibilità dei documenti.
6. Fare la verifica d'uso completa nell'app e solo dopo riprendere le estensioni tipografiche indipendenti.

Il primo incremento concreto sui campi è implementato. Il passo successivo in quest'area è estendere la grammatica a risultati e operazioni ulteriori, mantenendo l'ancoraggio, la ricomposizione, il salvataggio e l'aggiornamento senza duplicare i campi.
