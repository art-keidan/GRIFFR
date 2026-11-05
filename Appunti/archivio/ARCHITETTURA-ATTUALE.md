# GRIFFR: ricognizione dell'architettura attuale

4 novembre 2026 — tappa 2 del [piano](PIANO.md). Esame statico del codice nella copia del progetto: non è una verifica completa dell'app a schermo né una nuova esecuzione dei test. Le conclusioni sull'assenza di funzioni si riferiscono a quanto individuato nei componenti esaminati.

## Risultato principale

GRIFFR ha già una struttura di documento, stili ereditabili, alcune regole contestuali, proprietà calcolate dalla composizione e un ispettore della provenienza. Non dispone ancora di un sistema generale di operazioni componibili e riutilizzabili dall'utente. I comportamenti sono oggi distribuiti fra definizioni, editor e compositore; questo non implica che siano da buttare o riscrivere.

La caratteristica più importante per la riprogettazione è che **documento, testo vivo e pagine composte sono tre rappresentazioni collegate**, non lo stesso albero di oggetti persistente. La possibilità di passare dall'una all'altra esiste; l'identità e la posizione degli elementi però non hanno ovunque lo stesso significato.

## 1. Organizzazione e percorso dei dati

Il pacchetto Swift separa `Typesetting` — modello, composizione, font, PDF — dall'app `WordProcessor`. Entrambi hanno suite di test dedicate. Il motore usa anche AppKit e Core Text: «senza interfaccia» non significa indipendente da macOS. [Package.swift](../Package.swift)

Il percorso principale è:

```text
file .grx / .wpx
    ⇅ DocumentFormat
Document: struttura, contenuto, definizioni
    ⇅ AttributedBridge
DocumentStore: testo vivo con attributi e identità dei paragrafi
    → PageLayout + impostazioni → DocumentLayout: pagine, righe, posizioni
    → PagesView / ispettore / PDF
```

All'apertura `TextDocument` legge un `Document`; l'editor lo converte in testo con attributi. Al salvataggio, `currentDocument()` ricostruisce il modello dal testo corrente e dalle impostazioni. L'editor richiama `PageLayout.layout` per ricomporre e aggiornare le pagine. [TextDocument.swift](../Sources/WordProcessor/TextDocument.swift) · [AttributedBridge.swift](../Sources/Typesetting/AttributedBridge.swift) · [EditorWindowController.swift](../Sources/WordProcessor/EditorWindowController.swift)

## 2. Documento e identità

`Document` conserva impostazioni di pagina, stili, liste, stili di flottante, regole, tipi di pagina, blocchi e sezioni annidate. Una sezione ha ruolo, identità, titolo come `Paragraph`, blocchi e sottosezioni; i blocchi comprendono paragrafi e tabelle. Un paragrafo contiene tratti, immagini e flottanti. Le sezioni e le tabelle hanno identificativi nel modello; le celle sono rappresentate attraverso la struttura e la posizione nella tabella. [Document.swift](../Sources/Typesetting/Document.swift)

L'editor usa `DocumentStore`, un testo con attributi suddiviso internamente in paragrafi. Ogni paragrafo del corpo ha un `ParagraphID` che il deposito cerca di mantenere durante modifiche, divisioni, unioni e spostamenti secondo regole esplicite. È utile nell'editor, ma `Paragraph` nel modello salvato non contiene questo identificativo: non è quindi un riferimento persistente garantito attraverso salvataggio e riapertura. [DocumentStore.swift](../Sources/Typesetting/DocumentStore.swift)

Parole e righe possono essere individuate o calcolate; non sono tutte oggetti persistenti autonomi con identità salvata. La differenza fra «la quinta parola ora» e «questa parola specifica anche dopo una modifica» richiede ancora una scelta progettuale e, per il secondo caso, un meccanismo di ancoraggio persistente. Gli appunti già registrano questa esigenza per rimandi e annotazioni. [Appunti/da-fare.md](da-fare.md)

## 3. Stili e formattazione

Gli stili con nome hanno un bersaglio (`paragraph`, `word`, `character`), possono basarsi su un altro stile e specificano soltanto alcuni valori. La risoluzione combina eredità e livelli; le proprietà comprendono font e funzioni, lingua, rientri, spazi, lista, livello, distanza d'apertura e tenuta delle righe. `LineKeeping` comprende «tieni col seguente», «indivisibile» e minimi di righe alle estremità della pagina. [Styles.swift](../Sources/Typesetting/Styles.swift) · [LineKeeping.swift](../Sources/Typesetting/LineKeeping.swift)

I valori manuali coesistono con gli stili e, secondo il formato documentato, normalmente prevalgono su quelli ereditati. Le regole possiedono anche eccezioni per proprietà date a mano. Lo stile che apre una sezione determina il ruolo all'atto della creazione; il commento nel codice precisa che, in seguito, la sezione non dipende più da quello stile. [DocumentFormat.swift](../Sources/Typesetting/DocumentFormat.swift) · [Rules.swift](../Sources/Typesetting/Rules.swift) · [Styles.swift](../Sources/Typesetting/Styles.swift)

`NamedStyle` contiene nome, tipo, base e valori; non emerge un campo generale per espressioni, effetti o definizioni di operazioni utente. Le regole sono conservate separatamente nella raccolta `Document.rules`, pur potendo selezionare i paragrafi per stile.

## 4. Regole e contesto

`TextRule` riconosce bersagli predefiniti: prima lettera, prime N parole, prima frase, parole secondo alcuni modelli, prime righe, ultima riga o paragrafo. Può limitarsi a uno stile, al primo paragrafo dopo un altro stile, all'apertura di una sequenza o al primo di una pagina. Le condizioni numeriche disponibili riguardano numero di righe o parole, riempimento dell'ultima riga e righe sillabate. L'effetto è applicare uno stile al bersaglio: non è un motore generale di selezioni, operazioni componibili ed effetti arbitrari. [Rules.swift](../Sources/Typesetting/Rules.swift)

Le regole lavorano su una copia durante la composizione; la formattazione manuale può prevalere. Per le condizioni dipendenti dalla composizione il codice usa dati della composizione naturale preliminare. Anche «primo della pagina» è valutato in quel contesto, non come garanzia generale che la condizione resti vera nel risultato finale. [Rules.swift](../Sources/Typesetting/Rules.swift) · [PageLayout.swift](../Sources/Typesetting/PageLayout.swift)

La **distanza d'apertura** si può impostare nello stile o sul singolo paragrafo, ma il compositore la applica al paragrafo che apre una sequenza quando si trova in cima alla pagina. Non è una variante generale per qualsiasi paragrafo capitato in cima a una pagina. Il test `openingDistanceLayout` verifica il caso titolo su nuova pagina rispetto al titolo di seguito; non è stato rieseguito in questa ricognizione. [SectionTests.swift](../Tests/TypesettingTests/SectionTests.swift)

## 5. Informazioni dinamiche e composizione

`DocumentLayout` contiene pagine e righe composte. Una riga registra intervalli di testo, posizione del paragrafo, coordinate e larghezze; una pagina contiene righe, segni di lista, filetti, fondi e immagini. I riferimenti impiegano spesso posizioni e intervalli del testo: vanno interpretati rispetto alla composizione e al testo correnti. [PageLayout.swift](../Sources/Typesetting/PageLayout.swift)

`DynamicFacts` ricava informazioni su paragrafo, riga, pagina e documento, comprese pagine di inizio e fine, numero di righe e parole, presenza di note, riempimento e spazio libero. Questi dati sono preziosi per l'ispettore e alcuni comportamenti, ma non costituiscono ancora un catalogo generale di metodi concatenabili e definibili dall'utente. [DynamicFacts.swift](../Sources/Typesetting/DynamicFacts.swift)

Il compositore applica le regole, prepara il testo e costruisce le pagine. Per le note numerate per pagina e per il conteggio totale delle pagine può ripetere alcune passate, con un limite di tre iterazioni per ciascun caso. È un meccanismo specifico, non una soluzione generale per tutte le dipendenze cicliche. `layoutPages()` richiede la composizione dell'intero documento; il motore usa cache per composizione delle righe e a capo, quindi non va confuso con il ricalcolo senza alcun riuso. [PageLayout.swift](../Sources/Typesetting/PageLayout.swift) · [EditorWindowController.swift](../Sources/WordProcessor/EditorWindowController.swift)

## 6. Flottanti e campi

`FloatStyle` prevede collocazioni specializzate, fra cui piè di pagina, fine documento, margine esterno, figure, intestazioni e piè di pagina corrente. Un `FloatingObject` conserva paragrafi come sequenze di tratti, uno stile e un'eventuale immagine; non è lo stesso tipo `Paragraph` completo del corpo. Le tabelle possono anch'esse usare uno stile di flottante, attraverso una rappresentazione specifica. [Document.swift](../Sources/Typesetting/Document.swift)

Le note a margine vengono collocate accanto alla riga del richiamo con una distanza interna fissata dal codice; le sovrapposizioni e alcune uscite dal margine sono segnalate, non risolte automaticamente. La distanza dal bordo prevista per intestazioni e piè di pagina non è un parametro generale di collocazione delle note a margine. [PageLayout.swift](../Sources/Typesetting/PageLayout.swift)

I campi incorporati comprendono pagina, numero totale di pagine, titolo e numero della sezione corrente di un ruolo: sono relazioni calcolate già utili, ma non un meccanismo generale di rimando a un oggetto scelto. [Document.swift](../Sources/Typesetting/Document.swift)

## 7. Editor, interfaccia e spiegazione

Esistono già una modalità essenziale e una dettagliata: la seconda espone tra l'altro pannelli, ispettore e mappa degli oggetti. Non emerge un compositore visuale generale di espressioni. [EditorWindowController.swift](../Sources/WordProcessor/EditorWindowController.swift) · [MainMenu.swift](../Sources/WordProcessor/MainMenu.swift)

I comandi di tastiera sono gestiti dall'editor; Invio inserisce un separatore, con comportamenti particolari per elenchi e tabelle. Non è emersa nella definizione `NamedStyle` una proprietà generale «stile del paragrafo successivo»: l'eventuale comportamento completo in tutti i casi di Invio richiede una prova mirata, prima di concludere che sia assente ovunque. [EditorWindowController+Pagine.swift](../Sources/WordProcessor/EditorWindowController+Pagine.swift) · [Styles.swift](../Sources/Typesetting/Styles.swift)

L'ispettore ha una nozione di origine del valore: locale, stile, documento o regola; esistono anche segni della provenienza. È una base promettente per spiegare i risultati di regole più ricche, ma non dimostra che già oggi sia spiegabile una catena arbitraria di operazioni. [Inspection.swift](../Sources/Typesetting/Inspection.swift) · [Provenance.swift](../Sources/Typesetting/Provenance.swift)

## 8. Font e formato

Il codice gestisce funzioni AAT e OpenType, assi variabili e diverse altre proprietà tipografiche. Graphite è opzionale: se la libreria necessaria manca, il codice prevede il ripiego su Core Text e una segnalazione. Il supporto ai font è ampio ma questo esame non giustifica una promessa di supporto universale. [FontFeatures.swift](../Sources/Typesetting/FontFeatures.swift) · [FontVariations.swift](../Sources/Typesetting/FontVariations.swift) · [Graphite.swift](../Sources/Typesetting/Graphite.swift)

Il formato nativo è XML UTF-8, versione 1; l'estensione corrente è `.grx` e `.wpx` resta leggibile. Conserva stili, regole e strutture specifiche. Il lettore rifiuta elementi e attributi sconosciuti e versioni future: introdurre nuovi costrutti richiede quindi una strategia di versione, compatibilità e diagnosi, non la semplice aggiunta silenziosa di attributi. [DocumentFormat.swift](../Sources/Typesetting/DocumentFormat.swift) · [TextDocument.swift](../Sources/WordProcessor/TextDocument.swift)

## 9. Confronto con i casi guida

| Caso | Oggi | Da approfondire nella progettazione |
|---|---|---|
| Titolo più basso all'apertura | Distanza d'apertura per una sequenza; regola separata sul primo paragrafo di pagina. | Varianti generali di proprietà secondo la posizione e semantica quando la variante cambia l'impaginazione. |
| Titolo e capoverso successivo | Esistono tenuta col seguente e regole basate sullo stile precedente. | Azioni tra elementi, precedenze e comportamento configurabile di Invio. |
| Testata `memoir` | Sezione, titolo, numerazione, distanze e controlli tipografici esistono. | Non emerge un modello generale di testata composta da numero, titolo e filetti con relazioni configurabili. |
| Quinta parola e flottante | Selezione delle prime N parole; flottanti e note a margine specializzati. | Selezione dell'N-esima parola come risultato componibile, relazione con il flottante e collocazione parametrica. |
| Operazione riutilizzabile | Ci sono operazioni Swift e regole specializzate. | Definizioni componibili dall'utente, parametri, tipi e persistenza. |

## 10. Vincoli da portare alla tappa 3

- Esaminare l'impatto del nuovo modello sulle conversioni fra struttura, testo vivo e risultato composto; non assumere che una posizione UTF-16 sia un'identità durevole.
- Chiarire precedenze, eccezioni e origine dei valori, estendendo ciò che già esiste invece di duplicarlo senza necessità.
- Separare osservazioni disponibili prima della composizione, risultati derivati e azioni dell'editor; esplicitare come si evitano o si risolvono i cicli.
- Conservare e verificare comportamento dei documenti e test esistenti; progettare migrazione e versionamento prima di cambiare il formato.
- Misurare l'effetto delle nuove dipendenze sulle cache e sulla ricomposizione, senza assumere che il motore sia già incrementale o che debba essere riscritto.

Questa mappa prepara la progettazione; non sceglie ancora un'architettura futura né promette che ogni capacità attuale possa essere generalizzata senza modifiche.
