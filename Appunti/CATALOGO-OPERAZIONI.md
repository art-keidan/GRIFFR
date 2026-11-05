# GRIFFR · Primo vocabolario delle operazioni

Tappa 5 · Proposta del 4 novembre 2026

Il catalogo parte dai quattro [scenari verificati su carta](archivio/SCENARI-DI-VERIFICA.md). Introduce un piccolo insieme di famiglie di operazioni, con parametri espliciti, e mostra come ricavarne definizioni riutilizzabili. Le etichette italiane sono una proposta per il compositore visuale. I nomi fra parentesi servono per riferirsi alle operazioni durante la progettazione e potranno diventare identificativi nel formato.

La prima versione dovrebbe permettere di costruire la variante del titolo all'apertura della pagina, il trattamento del capoverso successivo, una testata composta e una nota associata alla quinta parola. Il catalogo comprende quanto occorre per descrivere questi casi, insieme alle condizioni di validità che il futuro prototipo dovrà verificare.

## 1 · La forma di un'operazione

Ogni scheda descrive l'oggetto ricevente, i parametri, il risultato, la disponibilità del risultato e le situazioni in cui questo può mancare. Un collegamento visuale trasporta un risultato verso un ingresso compatibile. La regola ha un proprietario, normalmente il capoverso che usa lo stile, e uno o più effetti finali. Per gli effetti la scheda indica anche chi conserva il contenuto e quali parti del documento possono cambiare.

L'operazione che trova la quinta parola restituisce una selezione di testo. Quella che misura il numero di parole restituisce un intero. Nell'interfaccia propongo di chiamarle rispettivamente **Scegli parola** e **Conta parole**, mantenendo l'intenzione dell'esempio originale «contare(parola, 5)». Entrambe possono derivare dalle famiglie generali qui sotto.

## 2 · Tipi e momenti di valutazione

| Tipo | Significato e regola di collegamento |
|---|---|
| Oggetto editoriale | Capoverso, sezione, tabella, flottante. I tipi restano distinti e possiedono riferimenti durevoli quando sono salvati. |
| Selezione testuale | Intervallo delimitato da grafemi in una revisione di testo. Una parola è una selezione con un criterio di segmentazione. |
| Carattere | Elemento testuale interrogabile e formattabile. L'unità esatta, grafema oppure codice Unicode, deve essere dichiarata nelle operazioni che ne dipendono. |
| Posizione | Punto di inserimento del cursore fra elementi del testo. Consente di interrogare il contesto del punto, come paragrafo, sezione e pagina. Una formula inserita come campo conserva un riferimento al proprio punto nel documento. |
| Raccolta ordinata di T | Elementi del medesimo tipo T, con ordine dichiarato. |
| Facoltativo di T | Un risultato che può mancare. La GUI richiede di gestire l'assenza prima di usarlo come oggetto obbligatorio. |
| Testo, intero, numero, booleano | Valori confrontabili secondo il loro tipo. |
| Lunghezza | Valore con unità. Millimetri e punti si possono convertire, un numero senza unità richiede una scelta esplicita. |
| Stile, regola, parte | Riferimenti a definizioni mediante identità stabile, con nome leggibile modificabile. |
| Frammento e pagina | Riferimenti alla composizione di una revisione specifica. Un capoverso può avere più frammenti. |
| Schema di composizione | Parti, contenuti, distanze e allineamenti da misurare e collocare. |

Le schede usano quattro momenti. **Struttura** legge contenuto e assegnazioni dell'autore. **Misura preliminare** legge un risultato composto con le varianti geometriche del nuovo sistema escluse. **Tentativo di pagina** legge il posto corrente in cui il compositore prova a collocare un blocco. **Risultato** legge una composizione accolta. **Evento** è un contesto separato fornito dall'editor quando registra un'azione.

Il momento si propaga attraverso i collegamenti. Un'espressione che usa la pagina finale eredita quella dipendenza anche quando è nascosta in una definizione riutilizzabile. Il validatore controlla anche quali proprietà può modificare l'effetto. Leggere la larghezza finale per cambiarla introduce una dipendenza che richiede una regola di soluzione.

## 3 · Nove famiglie per leggere e selezionare

| Operazione | Ricevente e parametri | Risultato | Disponibilità e comportamento |
|---|---|---|---|
| **Elementi** (elements) | Capoverso + unità «parole» o «grafemi», criterio di lingua e segmentazione | Raccolta ordinata di selezioni | Struttura. Si considera il testo del capoverso, con esclusione del testo di note e dei numeri generati. Il trattino di sillabazione composto resta estraneo al conteggio. |
| **Scegli** (item) | Raccolta + posizione intera a partire da 1, oppure «prima» o «ultima» | Facoltativo dell'elemento | Eredita il momento della raccolta. Oltre la fine restituisce assenza. Una posizione minore di 1 è una configurazione errata. |
| **Conta** (count) | Raccolta | Intero | Eredita il momento della raccolta. Una raccolta vuota dà zero. |
| **Leggi** (read) | Oggetto o selezione + proprietà compatibile | Valore del tipo della proprietà, eventualmente facoltativo | Struttura per testo, stile assegnato e ruolo. Le misure di composizione dichiarano il loro momento. Il selettore di proprietà offre solo proprietà registrate. |
| **Raggiungi** (related) | Oggetto + relazione e ambito | Oggetto facoltativo | Struttura. Le relazioni iniziali sono sezione contenente, titolo di sezione, blocco precedente e blocco successivo. |
| **Componi per misurare** (measure) | Capoverso + larghezza e profilo preliminare del contesto | Raccolta ordinata di frammenti di riga e relative misure | Misura preliminare. Il risultato registra font, larghezza e revisioni delle definizioni usate. |
| **Trova frammento** (locate) | Selezione + estremità iniziale/finale + contesto di composizione | Frammento di riga facoltativo | Risultato. Per l'estremità finale si usa l'ultimo grafema della selezione. Una selezione vuota richiede l'affinità esplicita del cursore. |
| **Contesto di pagina** (pageContext) | Blocco candidato oppure frammento accolto | Contesto con pagina, bordi e posizione nel flusso | Tentativo o Risultato, secondo l'ingresso. I due tipi di contesto sono riconoscibili nella GUI. |
| **Come tipo** (asType) | Oggetto + tipo desiderato | Oggetto facoltativo del tipo richiesto | Eredita il momento. Consente di chiedere un capoverso al blocco seguente. Se è una tabella il risultato manca. |

**Ambito della relazione.** Per il caso guida si usa «blocchi nello stesso corpo di sezione». Il titolo precede il primo blocco del corpo. Le celle di una tabella costituiscono corpi separati. Un confine di sezione interrompe il percorso. «Primo capoverso saltando le tabelle» può diventare una futura operazione, con una semantica propria.

**Proprietà iniziali.** Leggi espone testo e stile assegnato sui capoversi, ruolo e titolo sulle sezioni, numero formattato dove la Lista lo fornisce, larghezza e altezza sui frammenti. Sul contesto di pagina espone indice fisico, bordi del foglio e dello specchio, lato esterno e indicatore «primo posto nel flusso principale». Quest'ultimo è un fatto elementare del compositore, calcolato sul contenuto precedente al candidato. Il numero di pagina stampato è distinto dall'indice fisico, perché una numerazione riavviata non cambia il lato del foglio.

**Segmentazione.** Propongo di riutilizzare inizialmente la segmentazione già impiegata nel progetto, dopo averne fissato e verificato i casi di apostrofi, parole composte, cifre e scritture senza spazi. La definizione salva una versione del criterio. Un conteggio di «caratteri» nella GUI specifica «grafemi» oppure un'altra unità dichiarata. Le posizioni UTF-16 rimangono un dettaglio del ponte con l'editor.

## 4 · Cinque famiglie per combinare risultati

| Operazione | Ingressi | Uscita e comportamento |
|---|---|---|
| **Confronta** (compare) | Due valori compatibili + uguale/diverso/maggiore/minore | Booleano. L'identità degli oggetti e il confronto del loro testo sono scelte distinte. |
| **Combina condizioni** (logic) | Booleani + tutte/una almeno/negazione | Booleano. Le condizioni possono avere sottoespressioni finite. |
| **Se** (if) | Condizione + due rami di tipo compatibile | Il ramo selezionato. I rami ereditano entrambi le dipendenze statiche, pur valutando solo quello necessario. |
| **Quando presente** (whenPresent) | Facoltativo + ramo che riceve il valore presente | Ramo di regola eseguito quando c'è un bersaglio. In assenza, il motivo resta ispezionabile. |
| **Calcola** (calculate) | Quantità compatibili + somma/sottrazione/moltiplicazione/divisione | Quantità controllata per unità. Divisione per zero produce una diagnosi. Nel primo insieme si moltiplica o divide una lunghezza per un numero. |

Costanti, parametri, il proprietario dello stile e l'eventuale nuovo capoverso dell'evento sono ingressi visuali. Una definizione può chiamare altre definizioni fino a formare un grafo senza cicli. Il motore applica un limite esplicito di espansione e mostra quale definizione lo supera.

## 5 · Cinque famiglie di effetti

| Effetto | Ingressi | Proprietà del comportamento |
|---|---|---|
| **Dichiara proprietà** (declare) | Bersaglio, proprietà, valore, forza e priorità | Produce un contributo alla resa. Rientri, spazi, font, tenuta e distanza d'apertura usano questo meccanismo. La distanza nomina il bordo del blocco e il bordo dello specchio di riferimento. |
| **Tratta con stile** (applyAppearance) | Bersaglio e stile di trattamento | Espande le proprietà consentite dello stile di trattamento in contributi con provenienza. Gli eventi e le regole attive di quello stile richiedono un'attivazione separata. |
| **Assegna stile nell'editor** (assignStyle) | Capoverso creato dall'evento e stile | Modifica salvata e annullabile nella transazione di Invio. |
| **Componi apertura** (composeOpening) | Titolo proprietario, schema e gestione del numero | Produce il blocco che il motore deve misurare prima di collocarlo. Titolo, indice e mappa condividono il testo editoriale. La resa ordinaria del numero viene sostituita dalla parte numero dello schema. |
| **Presenta flottante** (presentFloat) | Proprietario, chiave di parte, selezione del richiamo, contenuto, stile e collocazione | Conserva il contenuto scritto per proprietario/regola/parte. La scatola appare se il richiamo è risolto. Ogni ricomposizione riutilizza quella stessa occorrenza logica. |

Dichiara proprietà e Tratta con stile sono proposte valutate dal risolutore. Per due contributi incompatibili si applicano le precedenze della [proposta architetturale](ARCHITETTURA-PROPOSTA.md). La definizione riutilizzabile può essere un'espressione pura oppure uno schema di effetto, dichiarato come tale. Uno schema di effetto produce dichiarazioni solo nel punto finale della regola, con un'identità per ciascuna chiamata.

Il flottante nel margine viene dichiarato prima della misura. Il motore determina poi la riga del richiamo e dispone il riquadro nel margine, seguendo la politica di collisione dichiarata. Se deve comparire un segno nel testo, la sua presenza e il suo spazio vengono inclusi nella misura precedente alla paginazione. Al primo insieme propongo di limitare questa collocazione derivata a note marginali che lasciano intatta la larghezza del corpo. Altri tipi potranno usare le procedure specializzate per note e figure esistenti.

## 6 · Uno schema visuale per le testate

La costruzione delle testate richiede quattro elementi visuali aggiuntivi.

| Elemento | Parametri essenziali |
|---|---|
| **Parte testuale** | Nome stabile, fonte del testo, stile, allineamento e altezza naturale o minima |
| **Filetto** | Nome, spessore, lunghezza e allineamento |
| **Spazio** | Lunghezza fra parti |
| **Sequenza verticale** | Parti ordinate, larghezza disponibile e bordo di riferimento |

Numero, titolo e parola «Capitolo» sono fonti diverse per la stessa Parte testuale. Un titolo più lungo aumenta l'altezza naturale. Un'eventuale altezza minima di 12 mm per il numero può crescere se il carattere lo richiede. L'allineamento al lato esterno viene risolto per il tentativo di pagina. Questi elementi rendono possibile la testata del caso guida. Composizioni sovrapposte o vincoli geometrici liberi richiedono ulteriori primitive da scegliere in seguito.

## 7 · Quattro espressioni da costruire nella GUI

### Apertura del capitolo

Ingresso «questo titolo» → Contesto di pagina del tentativo → Leggi «primo posto nel flusso principale» → ramo Se vero → Dichiara proprietà sul blocco di apertura, distanza 30 mm dallo specchio superiore.

Il compositore ricalcola la variante dopo un trasferimento dovuto alla tenuta. La spiegazione nomina la condizione e il bordo scelto. L'utente può aprire la stessa definizione con un controllo avanzato dedicato «Distanza quando apre pagina».

### Titolo e capoverso seguente

Per l'azione di scrittura, l'evento «Invio in fondo ha creato un capoverso» fornisce il nuovo oggetto → Assegna stile nell'editor «Corpo».

Per il trattamento del vicino, questo titolo → Raggiungi blocco successivo nello stesso corpo → Come tipo capoverso → Quando presente → Dichiara rientro prima riga 0 mm, obbligatorio.

Le due regole si possono attivare separatamente. Una tabella immediatamente successiva lascia inattivo il secondo ramo.

### Testata composta

Questo titolo → Raggiungi sezione contenente → Leggi numero formattato → Parte testuale «numero».

Questo titolo → Leggi testo → Parte testuale «titolo».

Sequenza verticale di numero, spazio 3 mm, filetto 0,5 mm, spazio 2,5 mm e titolo → Componi apertura, con 8 mm dopo e resa del numero gestita dallo schema.

Per la disposizione del caso guida il numero ha altezza minima 12 mm. Le righe del titolo sono misurate con il font e l'interlinea scelti. La distanza d'apertura agisce sul blocco risultante.

### Nota sulla quinta parola

Questo capoverso → Elementi parole → Scegli 5 → Quando presente → Presenta flottante con parte «nota», contenuto scritto dal proprietario e capoverso di stile X.

La collocazione dichiara il bordo esterno del riquadro a 10 mm dal bordo fisico esterno del foglio e la prima linea di base allineata alla riga dell'estremità finale del richiamo. Il motore usa Trova frammento e Contesto di pagina dopo aver composto il richiamo. Se manca la quinta parola, l'effetto di resa resta inattivo e il contenuto salvato rimane nel proprietario.

L'autore può selezionare Elementi parole → Scegli N, nominare la combinazione **Parola del richiamo** ed esporre N come parametro. Una modifica a questa definizione aggiorna le regole che la richiamano. Una copia esplicitamente indipendente riceve una nuova identità.

## 8 · Salvataggio, limiti e verifiche prima dell'implementazione

Una definizione con nome conserva identità, parametri tipizzati, uscita, grafo dei collegamenti, versione delle primitive e disposizione visuale. Il controllo semplice modifica la stessa definizione attraverso un adattatore verificabile. Rinominare cambia l'etichetta. Rimuovere una definizione ancora richiamata produce una diagnosi dei punti d'uso. L'eventuale sostituzione viene scelta esplicitamente.

Il primo perimetro ammette espressioni finite, richiami senza ricorsione, selezioni delimitate, schemi di composizione e i cinque effetti registrati. Le azioni di scrittura sono legate a eventi conosciuti dell'editor. Gli effetti da geometria finale sono ammessi dove il motore garantisce la direzione delle dipendenze, come la nota marginale appena descritta. Il profilo preliminare esclude tutte le nuove varianti geometriche per dare un significato comune a «prima della variante». Importare le regole precedenti richiederà un confronto specifico, perché la loro misura naturale può seguire fasi diverse.

Le 19 famiglie di operazioni ed effetti e i quattro elementi di testata sono una proposta iniziale. La ricchezza effettiva dipende anche dal catalogo delle proprietà e relazioni registrate. Le prossime prove devono verificare i quattro percorsi nel compositore, la gestione dell'assenza, i controlli di unità, una definizione riutilizzata due volte e la persistenza di una nota sospesa. Solo dopo quei riscontri sarà opportuno fissare i nomi e le firme nel formato del documento.

## 9 · Carattere, posizione e formule inserite come campi

L'ideatore ha aggiunto **Carattere** e **Posizione** all'insieme degli oggetti. Posizione indica la posizione del cursore. Carattere deve essere raggiungibile come elemento e fornire contenuto e proprietà tipografiche. La scelta di usare il grafema come unità predefinita resta una proposta tecnica.

L'ideatore ha confermato il funzionamento analogo ai campi di Word. Quando si inserisce una formula nel testo, il cursore determina il punto in cui nasce il campo. La formula rimane associata a quel punto e ne ricava il contesto quando viene rivalutata.

Per esempio **Posizione → Pagina contenente → Numero** mostra il numero della pagina in cui si trova il campo. **Posizione → Sezione contenente → Titolo** può mostrare il titolo della sezione relativa al campo. Le etichette dei passaggi sono illustrative e richiedono la definizione delle relative operazioni.

Il campo conserva la formula e il proprio riferimento nel documento. Il valore visualizzato deriva dalla valutazione. Scrivendo prima del campo si sposta anche il riferimento. La ripaginazione può cambiare il risultato. La posizione corrente dell'editor e quella conservata da un campo sono due usi dello stesso concetto, con durata diversa.

Questa estensione richiede di progettare il campo come proprietario di una formula, oltre alle formule appartenenti agli stili. Nel compositore occorrerà rendere riconoscibile il contesto di valutazione. L'aggiornamento rispetto all'impaginazione deve seguire le regole sulle dipendenze già discusse, in particolare quando il valore del campo può cambiare la larghezza del testo.

L'oggetto Posizione e i campi con formule componibili sono un'estensione del catalogo, ancora da implementare.

## 10 · Scrivi risultato e struttura interna comune degli stili

L'ideatore ha approvato l'effetto **Scrivi risultato**, con destinazione Posizione, valore calcolato e stile del testo prodotto. Un campo conserva formula e riferimento e presenta il risultato aggiornato nella medesima occorrenza.

L'ideatore richiede inoltre che tutti gli stili abbiano internamente la struttura delle formule, comprese le proprietà costanti. La riformulazione delle definizioni attuali è nell'[archivio](archivio/STILI-COME-FORMULE.md). Il catalogo comprende ora 20 famiglie, contando Scrivi risultato. La traduzione degli stili evidenzia altre firme da precisare, comprese eredità, numerazione e apertura strutturale di sezione.

## 11 · Predicati con effetto Imposta, Aggiungi e Sottrai

L'ideatore distingue **Imposta(bersaglio, proprietà, valore)** e **Aggiungi(bersaglio, proprietà, valore)**. Proprietà come Font e Spazio prima sono argomenti del predicato. Per Font, Imposta Grassetto sceglie il ruolo completo grassetto, anche se prima il carattere era corsivo. Aggiungi Grassetto conserva il corsivo e produce grassetto corsivo.

Imposta corrisponde alla dichiarazione sostitutiva. Aggiungi introduce una composizione tipizzata del valore ricevuto e della modifica richiesta. Le modalità ammesse dipendono dalla proprietà. La forza obbligatoria o derogabile rimane distinta dalla scelta del predicato. Il catalogo comprende ora 21 famiglie contando anche Aggiungi.

La [riformulazione archiviata degli stili](archivio/STILI-COME-FORMULE.md) adotta Aggiungi per i tratti parziali dei predefiniti attuali e separa le pills del predicato da quelle della proprietà.

Sottrai(bersaglio, proprietà, valore) rimuove i tratti richiesti dal font oppure sottrae una misura dal valore ricevuto. Grassetto corsivo meno Grassetto produce Corsivo; 12 pt meno 6 pt produce 6 pt. È la ventiduesima famiglia del catalogo. [Contratto e implementazione archiviati](archivio/SOTTRAI.md).
