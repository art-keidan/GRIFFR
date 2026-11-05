# Gli stili attuali riformulati come formule

4 novembre 2026 · Traduzione del modello esistente e proposta di struttura comune

L'ideatore richiede che **tutti gli stili abbiano internamente la struttura delle formule**. Anche una proprietà ordinaria può essere una formula senza condizioni, con un oggetto e un effetto. Uno stile raccoglie formule, le eventuali basi ereditate e le azioni legate a eventi. Il compositore rende visibile questa struttura. I controlli semplici modificano gli argomenti delle stesse formule.

Questo documento traduce le definizioni lette nel codice e nei campioni del fork. Le espressioni sono una notazione di progetto per le pills. La conversione del modello Swift, del formato e di tutti i controlli richiede un successivo intervento. La bacheca attuale gestisce un sottoinsieme di selezioni e trattamenti.

## Grammatica comune

Una formula parte da un oggetto o da un evento, usa predicati con argomenti e termina con uno o più effetti. Il punto di partenza implicito è **Questo oggetto**, cioè l'occorrenza che riceve lo stile. Ogni riga seguente rappresenta una formula distinta.

- **[Questo paragrafo] → [Imposta] [Allineamento] [Giustificato]**
- **[Questo paragrafo] → [Caratteri contenuti] → [Imposta] [Corpo] [12 pt]**
- **[Questa parola] → [Imposta] [Lingua] [Italiano]**
- **[Questa posizione] → [Pagina contenente] → [Leggi] [Numero formattato] → [Scrivi risultato] [Qui]**

Nell'ultima espressione il punto di partenza, la destinazione e l'eventuale stile del testo prodotto sono argomenti riconoscibili. Il campo viene creato una volta e rivalutato. Un aggiornamento sostituisce la sua resa nella medesima occorrenza.

**Imposta** è un predicato con effetto. Riceve separatamente il bersaglio, la proprietà e il valore. **Aggiungi** è un altro predicato con effetto, che combina un valore con quello ricevuto dal contesto. Un argomento costante può essere sostituito da un valore calcolato dello stesso tipo. Ad esempio il corpo può essere una misura costante oppure il risultato di una formula sulla larghezza disponibile.

**Eredita** richiama le formule della base nel medesimo contesto. Le dichiarazioni dello stile derivato prevalgono per le proprietà che specificano, secondo le precedenze del risolutore. Un valore assente conserva l'eredità. «Disattivato» e zero sono dichiarazioni esplicite dove la proprietà li ammette. L'eredità deve conservare anche le regole attuali per il cambio di famiglia o faccia e il ripristino delle funzioni del font.

## Stili predefiniti di paragrafo

### Testo

- [Questo paragrafo] → [Caratteri contenuti] → [Imposta] [Famiglia] [Hoefler Text]
- [Questo paragrafo] → [Caratteri contenuti] → [Imposta] [Corpo] [12 pt]
- [Questo paragrafo] → [Imposta] [Allineamento] [Giustificato]

### Titolo 1

- [Questo paragrafo] → [Eredita] [Testo]
- [Questo paragrafo] → [Caratteri contenuti] → [Imposta] [Corpo] [18 pt]
- [Questo paragrafo] → [Caratteri contenuti] → [Aggiungi] [Font] [Grassetto]
- [Questo paragrafo] → [Imposta] [Allineamento] [Naturale]
- [Questo paragrafo] → [Imposta] [Spazio prima] [18 pt]
- [Questo paragrafo] → [Imposta] [Spazio dopo] [6 pt]
- [Questo paragrafo] → [Imposta] [Livello di paragrafazione] [1]
- [Quando questo stile viene assegnato] → [Paragrafo destinatario] → [Apri sezione] [Ruolo capitolo]

L’aggiunta del grassetto conserva il corsivo ricevuto dal contesto e usa le scelte tipografiche e le equivalenze di famiglia dell'app. L'apertura della sezione è un effetto strutturale nell'editor. Nel comportamento attuale una sezione già creata continua a esistere se in seguito si cambia lo stile del suo titolo. La formula deve rispettare questa durata.

### Titolo 2 e Titolo 3

Entrambi ereditano Testo e usano la stessa struttura di Titolo 1. Queste sono le formule proprie, con i rispettivi argomenti.

| Effetto sul bersaglio | Titolo 2 | Titolo 3 |
|---|---|---|
| Caratteri → Imposta corpo | 14 pt | 13 pt |
| Caratteri → Aggiungi al font | Grassetto | Grassetto |
| Paragrafo → Imposta allineamento | Naturale | Naturale |
| Paragrafo → Imposta spazio prima | 12 pt | 10 pt |
| Paragrafo → Imposta spazio dopo | 4 pt | 3 pt |
| Paragrafo → Imposta livello | 2 | 3 |
| Assegnazione dello stile → Apri sezione | Ruolo sezione | Ruolo sezione |

### Citazione

- [Questo paragrafo] → [Eredita] [Testo]
- [Questo paragrafo] → [Caratteri contenuti] → [Imposta] [Corpo] [11 pt]
- [Questo paragrafo] → [Imposta] [Rientro sinistro] [24 pt]
- [Questo paragrafo] → [Imposta] [Rientro destro] [24 pt]
- [Questo paragrafo] → [Imposta] [Spazio prima] [6 pt]
- [Questo paragrafo] → [Imposta] [Spazio dopo] [6 pt]

### Esempio

- [Questo paragrafo] → [Eredita] [Testo]
- [Questo paragrafo] → [Imposta] [Allineamento] [Naturale]
- [Questo paragrafo] → [Imposta] [Spazio prima] [6 pt]
- [Questo paragrafo] → [Imposta] [Spazio dopo] [6 pt]
- [Questo paragrafo] → [Associa numerazione] [Lista Esempi]

La Lista conserva il contatore condiviso e le regole di numerazione. La composizione ne ricava il segno da presentare, mantenendo il rapporto con gli altri elementi numerati.

### Sottoesempio

- [Questo paragrafo] → [Eredita] [Esempio]
- [Questo paragrafo] → [Imposta] [Spazio prima] [0 pt]
- [Questo paragrafo] → [Imposta] [Spazio dopo] [0 pt]
- [Questo paragrafo] → [Associa numerazione] [Lista Sottoesempi]

## Stili di parola, carattere e trattamento

| Stile | Formula |
|---|---|
| Latino | [Questa parola] → [Imposta] [Lingua] [Latino, la] |
| Greco antico | [Questa parola] → [Imposta] [Lingua] [Greco antico, grc] |
| Enfasi | [Caratteri destinatari] → [Aggiungi] [Font] [Corsivo] |
| Forte | [Caratteri destinatari] → [Aggiungi] [Font] [Grassetto] |
| Maiuscoletto | [Caratteri destinatari] → [Imposta] [Maiuscoletto] [Delle minuscole] |
| Maiuscoletto delle sigle | [Caratteri destinatari] → [Imposta] [Maiuscoletto] [Delle maiuscole] |
| Centrato | [Questo paragrafo] → [Imposta] [Allineamento] [Centrato] |

I caratteri destinatari sono quelli su cui lo stile è assegnato, anche quando formano una parola o un intervallo. Il maiuscoletto conserva il testo scritto e ne chiede una resa tipografica. Centrato è uno stile di trattamento proposto alle regole e fissa soltanto l'allineamento.

[Definizioni predefinite e risoluzione](../Sources/Typesetting/Styles.swift)

## Proprietà degli stili che possono essere personalizzate

La traduzione vale anche per proprietà che i predefiniti lasciano ereditate. La tabella copre i campi di StyleValues e le quattro proprietà di tenuta.

| Proprietà attuale | Formula equivalente |
|---|---|
| Faccia precisa | [Caratteri] → [Imposta] [Faccia] [Nome PostScript] |
| Famiglia e corpo | [Caratteri] → [Imposta] [Proprietà scelta] [Valore] |
| Nero e corsivo parziali attuali | [Caratteri] → [Aggiungi] [Font] [Tratto scelto] |
| Ruolo completo desiderato | [Caratteri] → [Imposta] [Font] [Ruolo completo] |
| Funzioni AAT e OpenType | [Caratteri] → [Imposta] [Funzioni tipografiche] [Impostazioni] |
| Assi variabili | [Caratteri] → [Imposta] [Assi del font] [Valori] |
| Corpo ottico | [Caratteri] → [Imposta] [Scelta ottica] [Automatica o variante] |
| Colore | [Caratteri] → [Imposta] [Colore] [Valore o automatico] |
| Apice e pedice | [Caratteri] → [Imposta] [Posizione verticale] [Tipo o parametri] |
| Decorazioni | [Caratteri] → [Imposta] [Filetti del testo] [Definizioni] |
| Motore di composizione | [Caratteri] → [Imposta] [Composizione] [Scelta e funzioni Graphite] |
| Maiuscoletto | [Caratteri] → [Imposta] [Maiuscoletto] [Modalità] |
| Lingua e sillabazione | [Parole destinatarie] → [Imposta] [Proprietà scelta] [Valore] |
| Allineamento, tre rientri, spazi prima e dopo, interlinea, spazio fra righe | [Paragrafo] → [Imposta] [Proprietà scelta] [Misura o modalità] |
| Lista | [Paragrafo] → [Associa numerazione] [Lista o nessuna] |
| Apertura di sezione | [Assegnazione dello stile] → [Paragrafo] → [Apri sezione] [Ruolo] |
| Livello | [Paragrafo] → [Imposta] [Livello] [Numero o nessuno] |
| Distanza d'apertura storica | [Paragrafo] → [Se apre una sequenza in cima alla pagina] → [Imposta] [Distanza superiore] [Misura] |
| Distanza a inizio pagina | [Paragrafo] → [Contesto di pagina] → [Se primo del flusso] → [Imposta] [Distanza superiore] [Misura] |
| Tieni col seguente | [Paragrafo] → [Successivo nel flusso] → [Richiedi tenuta comune] [Attiva o disattiva] |
| Indivisibile | [Paragrafo] → [Richiedi] [Conservare tutte le righe sulla stessa pagina] |
| Orfane e vedove | [Paragrafo] → [Richiedi] [Minimo righe al piede / in testa] [Numero] |

La proprietà di tenuta esprime un vincolo che il motore deve risolvere prima di collocare definitivamente il testo. La formula deve mantenere i ripieghi previsti quando il contenuto è più alto di una pagina.

## Stili di tabella

I valori iniziali del programma comprendono filetti di 0,5 pt, margini interni di 4 pt, testo in alto e fondo trasparente. Lo stile dichiara i valori propri sopra questa base, poi si applicano le eccezioni della tabella e delle celle.

| Stile | Formule proprie |
|---|---|
| Griglia | [Tabella] → [Imposta] [Filetti] [Tutti i bordi delle celle] |
| Tre filetti | [Tabella] → [Imposta] [Filetti] [Sopra, sotto intestazione, in fondo] e [Filetti] → [Imposta] [Spessore] [0,75 pt] |
| Orizzontali | [Tabella] → [Imposta] [Filetti] [Solo orizzontali] |
| Bordo | [Tabella] → [Imposta] [Filetti] [Solo perimetro esterno] |
| Senza filetti | [Tabella] → [Imposta] [Filetti] [Nessuno] |

Margini interni, allineamento verticale e sfondo diventano formule sulle celle destinatarie. Le misure dei filetti si riferiscono alle geometrie delle celle dopo la composizione.

[Stili di tabella](../Sources/Typesetting/TableAppearance.swift)

## Stili di flottante

### Nota a piè di pagina

- [Questo flottante] → [Richiamo] → [Pagina contenente] → [Colloca contenuto] [Al piede dello specchio]
- [Questo flottante] → [Associa numerazione] [Lista scelta o numerazione semplice]
- [Richiamo] → [Mostra numero] [In apice]
- [Blocco della serie di note] → [Mostra separatore] [Attivo]
- [Separatore] → [Imposta] [Lunghezza] [Minimo fra un terzo della giustezza e 144 pt]
- [Blocco della serie] → [Imposta] [Spazio sopra] [7 pt]
- [Blocco della serie] → [Imposta] [Spazio sotto il separatore] [4 pt]
- [Contenuto] → [Consenti divisione fra pagine] [Sì]

Il separatore e i suoi spazi appartengono al blocco della serie. La formula deve produrli una volta per blocco, anche quando vi arrivano più note. Lo stile del contenuto è un eventuale argomento aggiuntivo.

### Figura

- [Questo flottante] → [Associa numerazione] [Lista Figure]
- [Questo flottante] → [Richiedi collocazione] [Qui, in cima, in fondo, pagina di figure, in quest'ordine]
- [Questo flottante] → [Mostra richiamo nel corpo] [No]
- [Questo flottante] → [Mostra separatore] [No]
- [Didascalia] → [Colloca] [Sotto l'immagine]

### Tabella flottante

Usa la struttura di Figura con la Lista Tabelle e la didascalia sopra il contenuto. Questo stile nasce quando una tabella viene resa flottante.

### Intestazione e piè di pagina corrente

- [Questo flottante] → [Richiedi ripetizione] [Dalla sua ancora fino alla sostituzione]
- [Pagine destinatarie] → [Seleziona] [Tutte, pari, dispari o prima della sezione]
- [Contenuto] → [Colloca] [In testa / al piede della pagina]
- [Contenuto] → [Imposta] [Distanza dal bordo] [Misura o centro del margine]
- [Richiamo] → [Mostra] [No]
- [Separatore] → [Mostra] [No]
- [Contenuto] → [Consenti divisione] [No]

Queste sono le famiglie create dalle funzioni predefinite. La nota a margine e la nota di chiusura sono collocazioni disponibili configurando uno stile. In formule diventano rispettivamente «richiamo → riga → margine esterno» e «fine del documento → raccogli contenuti della serie».

[Definizioni dei flottanti](../Sources/Typesetting/Document.swift)

## Liste e scrittura del risultato

Le Liste condivise restano oggetti con stato di numerazione. Le formule chiedono il valore attribuito all'elemento e lo formattano. La resa deve mantenere i segni di lista come elementi generati, senza inserirli ripetutamente nel testo modificabile.

| Lista predefinita | Presentazione del valore |
|---|---|
| Elenco numerato | Decimale seguito da punto |
| Esempi | Decimale tra parentesi, numerazione continua |
| Sottoesempi | Lettera minuscola seguita da punto, con relazione alla Lista Esempi |
| Note | Decimale, numerazione continua |
| Note a simboli | Serie di segni tipografici, con riavvio legato alla pagina |
| Figure | «Figura » + decimale + punto |
| Tabelle | «Tabella » + decimale + punto |

Una formula tipica è **[Questo elemento] → [Valore nella Lista Esempi] → [Formatta tra parentesi] → [Scrivi risultato] [Posto del segno]**. Occorre distinguere il posto generato del segno dal campo inserito nel testo.

Per i campi già esistenti nel programma, le traduzioni sono **Posizione → pagina → numero formattato → Scrivi qui**, **Documento → totale pagine → Scrivi qui**, **Posizione → sezione corrente del ruolo scelto → titolo/numero → Scrivi qui**.

[Liste](../Sources/Typesetting/Lists.swift) · [Campi](../Sources/Typesetting/Document.swift)

## Stili dei campioni presenti in Appunti

Queste definizioni sono proprie dei file di esempio. Non sostituiscono i predefiniti del programma.

| Campione | Stile | Formule proprie |
|---|---|---|
| prova-apertura-pagina | Corpo | Paragrafo → caratteri → corpo 12 pt, paragrafo → spazio dopo 8 pt |
| prova-apertura-pagina | Titolo di capitolo | Caratteri → corpo 22 pt, spazio prima 12 pt, dopo 8 pt, tieni col seguente, quando primo della pagina → distanza 30 mm |
| prova-compositore | Titolo | Caratteri → corpo 26 pt, spazio dopo 20 pt |
| prova-compositore | Testo | Spazio dopo 12 pt |
| prova-compositore | Citazione | Rientro sinistro 15 pt, spazio dopo 12 pt |
| prova-compositore | Richiamo rosso | Caratteri destinatari → colore #9c2326 e corpo 19 pt |
| prova-compositore | Richiamo blu | Caratteri destinatari → colore #215f84 e corpo 19 pt |

Il campione Annapurna conserva molti nomi dei predefiniti, con valori definiti nel proprio XML. La traduzione si ottiene dalle dichiarazioni effettive del file. Per esempio il suo Titolo 1 dichiara corpo 18 pt, nero, allineamento naturale, spazio prima 18 pt e dopo 6 pt ed eredita Testo. Eventuali comportamenti ricavati dalle convenzioni di lettura del formato v1 vanno esplicitati separatamente dalle dichiarazioni scritte.

## Conseguenza per la bacheca e la migrazione

Ogni stile dovrà comparire come una scheda che raccoglie tutte le sue formule. Il controllo «Corpo» nell'interfaccia semplice e l'argomento «12 pt» nella pill dell'effetto devono modificare la stessa definizione. Le selezioni condivise possono essere richiamate da più formule e gli effetti «Scrivi risultato» producono campi o parti generate con una propria identità.

I nuovi effetti strutturali e di collocazione nominati in questo documento richiedono firme precise e verifiche nel motore. La conversione dovrà dimostrare equivalenza su font, testo, eredità, valori locali, liste e geometria. La riformulazione delle formule qui consegnata prepara quell'intervento.

## Imposta e Aggiungi

Precisazione dell'ideatore. Il predicato è **Imposta**, mentre Font, Corpo, Spazio prima e le altre proprietà sono argomenti. **Aggiungi** combina una modifica con lo stato ricevuto dal contesto.

| Formula sul carattere | Stato ricevuto | Risultato |
|---|---|---|
| [Imposta] [Font] [Grassetto] | Corsivo | Grassetto |
| [Aggiungi] [Font] [Grassetto] | Corsivo | Grassetto corsivo |
| [Imposta] [Font] [Corsivo] | Grassetto | Corsivo |
| [Aggiungi] [Font] [Corsivo] | Grassetto | Grassetto corsivo |

Per l'argomento Font, i ruoli completi devono essere distinti da famiglia, faccia precisa e corpo. Impostare il ruolo Grassetto sostituisce la combinazione dei tratti, mantenendo la famiglia salvo una diversa istruzione esplicita. L'aggiunta del grassetto conserva il corsivo. Questa distinzione riguarda l'effetto sul font. L'eventuale prevalenza sulla formattazione locale resta una proprietà distinta della regola.

Nel programma attuale Forte ed Enfasi fissano un tratto e conservano quello non specificato. Per mantenerne il comportamento la loro traduzione usa quindi **Aggiungi**, così come i titoli predefiniti che dichiarano il solo nero.

Per le lunghezze, la proposta naturale è [Imposta] [Spazio prima] [6 pt], che stabilisce 6 pt, e [Aggiungi] [Spazio prima] [6 pt], che somma 6 pt al valore in ingresso. Per insiemi di funzioni del font o decorazioni servirà specificare l'operazione di composizione ammessa dal tipo.

Ogni rivalutazione riparte dallo stato in ingresso della formula nella catena corrente. Aggiungere 6 pt a 12 pt deve dare 18 pt anche dopo cento ricomposizioni. Il risultato della passata precedente non diventa automaticamente l'ingresso della successiva.
