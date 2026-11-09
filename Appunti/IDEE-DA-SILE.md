# Idee da SILE per GRIFFR

Appunti raccolti il **9 novembre 2026**, su richiesta dell'ideatore: conservare tutte le idee emerse dalla ricognizione di SILE, senza decidere ora quali realizzare.

**Stato di questo documento:** raccolta di riferimenti, proposte e domande tecniche. Non è una specifica approvata, una promessa di funzionalità o una nuova sequenza obbligatoria di sviluppo. Le parti «Proposta per GRIFFR» sono nostre ipotesi progettuali; non descrivono capacità già esistenti in SILE o in GRIFFR.

## 1. Contesto della ricognizione

Fonti principali:

- sito ufficiale: <https://sile-typesetter.org/>;
- repository: <https://github.com/sile-typesetter/sile>;
- manuale consultato: [The SILE Book, versione 0.15.12](https://sile-typesetter.org/manual/sile-0.15.12.pdf);
- riferimenti Lua e Rust collegati dal sito.

Il numero del manuale indica il materiale esaminato, **non un'affermazione sull'ultima versione disponibile**. Non è stata installata né eseguita una copia di SILE. Alcune pagine del codice e dell'API non erano recuperabili direttamente: dove disponibile si è usata la documentazione indicizzata dello stesso progetto; non si dà per esaminata un'implementazione che non si è riusciti a leggere.

Il progetto GRIFFR è ora in `/Users/artemio/GRIFFR`, con app corrente `build/GRIFFR.app`. Il precedente percorso `WordProcessor/GRIFFR-fork-stili` non è più quello attuale.

Per il confronto sono stati letti `CLAUDE.md` e `Appunti/RIASSUNTO-RESIDUO.md`. Questi documenti registrano sviluppi successivi alla prima discussione sulle formule: interfaccia inglese, formato minimo 18, campi come formule, «Write Result» negli stili, testate di capitolo e navigazione nel PDF. Sono informazioni degli appunti del progetto, non una nuova verifica del codice o dell'app.

Di conseguenza, i seguenti spunti vanno valutati come estensioni, generalizzazioni o strumenti di consolidamento. Non bisogna ripartire da zero su campi, testate o PDF fingendo che manchino.

## 2. Perché SILE è interessante per questa ricerca

SILE si presenta come sistema di composizione programmabile, con idee provenienti da TeX e dai sistemi a riquadri. È un riferimento utile per interrogarsi su come rappresentare intenzioni tipografiche e trasformarle in impaginazione. [Presentazione ufficiale](https://sile-typesetter.org/what-is-sile/)

Per GRIFFR la domanda utile è: **quali concetti del motore possono diventare oggetti e azioni comprensibili nel compositore visuale?** La qualità dell'interfaccia dipende anche da quanto chiaramente il modello distingue misure, oggetti persistenti, risultati della composizione e richieste al motore.

Non è stata valutata la sostituzione del motore di GRIFFR con SILE. I riferimenti descritti qui possono servire anche mantenendo l'app nativa Swift/AppKit/SwiftUI/Core Text.

## 3. Riepilogo delle caratteristiche di SILE verificate nel manuale

Questo breve riepilogo raccoglie i fatti del manuale usati negli appunti; gli sviluppi delle sezioni successive sono proposte nostre.

- I *frames* possono essere definiti attraverso relazioni geometriche e collegati per il flusso del testo. Il modello del libro coordina anche il confine fra corpo e note.
- `infonode` inserisce marcatori informativi nel flusso; alla produzione della pagina si possono raccogliere le informazioni appartenenti a quella pagina.
- `parallel`, indicato come sperimentale, e l'esempio `diglot` mostrano flussi paralleli con punti di sincronizzazione.
- Il manuale tratta inserzioni e note marginali, ma ciò non dimostra una soluzione generale pronta per ogni collisione o rapporto fra oggetti.
- La documentazione segnala limiti dell'algoritmo di `balanced-frames`: non va assunto come soluzione già ottimale al bilanciamento delle colonne.

Riferimenti: [manuale, frames, progettazione delle classi, infonode e testi paralleli](https://sile-typesetter.org/manual/sile-0.15.12.pdf).

---

## 4. Misure che conservano il proprio significato

### Spunto documentato

Il tipo `measurement` di SILE conserva quantità e unità; alcune unità dipendono dal contesto. La conversione in misura assoluta è un'operazione esplicita. Sono documentati esempi come `3em` e `2%fw`. [API measurement](https://sile-typesetter.org/lua-api/types/measurement.html)

### Proposta per GRIFFR

Una misura può significare «due corpi del font corrente», «un decimo dello specchio» o «tre interlinee», oltre a un numero di punti. Sarebbe utile conservare nel documento questa intenzione e risolverla nel contesto appropriato.

Esempi concettuali:

```text
Left indent = 2 × Current font size
Rule width = 50% × Text frame width
Opening distance = 3 × Baseline spacing
Image width = Available width − Inner padding − Outer padding
```

Questi esempi descrivono possibili relazioni di GRIFFR; non sono sintassi SILE né comandi già implementati nell'app.

### Rappresentazione da studiare

Distinguere almeno:

- quantità assoluta, come 12 pt;
- quantità relativa al font;
- quantità relativa a pagina, specchio o riquadro;
- quantità relativa a una griglia o a una proprietà di stile;
- risultato risolto per uno specifico contesto di composizione.

L'espressione salvata deve restare separata dal numero effettivo usato per disegnare. L'ispettore potrebbe mostrare entrambi:

```text
Definition: 2 × font size
Context: Body, 11 pt
Effective value: 22 pt
```

### Questioni da decidere

- «Font corrente» significa il font ricevuto dalla formula o il risultato dopo le altre formule dello stile?
- Una percentuale di larghezza si riferisce alla pagina fisica, allo specchio o alla cella contenente?
- La misura cambia quando l'oggetto passa da una colonna all'altra?
- Una formula può leggere una proprietà che sta modificando? Se sì, quale ingresso legge?
- Una misura relativa può essere usata come argomento di un'altra formula senza risolverla subito?

### Verifiche utili

Cambio di corpo del font, cambio formato carta, pagine con specchi diversi, celle di larghezza differente, applicazione dello stesso stile in contesti diversi, salvataggi ripetuti senza accumulo del risultato. Per esempio, rivalutare «corpo + 2 pt» non deve continuare ad aggiungere 2 pt al risultato precedente.

**Legame con il progetto:** formule, tipi delle quantità, argomenti delle azioni, testate e futura migrazione di celle e flottanti.

## 5. Spazi elastici: minimo, preferito e massimo

### Spunto documentato

Il tipo `length` di SILE combina una misura normale con due quantità, `stretch` e `shrink`, che descrivono quanto può espandersi o contrarsi. [API length](https://sile-typesetter.org/lua-api/types/length.html)

### Proposta per GRIFFR

Alcune distanze potrebbero esprimere un intervallo accettabile, con un valore preferito:

```text
Space before: minimum 9 pt, preferred 12 pt, maximum 18 pt
```

La traduzione concettuale verso i tre componenti sarebbe: base 12, contrazione consentita 3, espansione consentita 6. I nomi nell'interfaccia possono restare editoriali, senza obbligare a conoscere il termine «glue».

Possibili impieghi:

- spazio prima e dopo un paragrafo;
- separazione fra testata e corpo;
- distanza fra elementi di una testata composta;
- spazio fra note della stessa serie;
- spazio sopra un gruppo di note;
- distribuzione verticale in una pagina corta.

### Politica di composizione da progettare

Non basta aggiungere tre campi: occorre decidere come il motore sceglie il valore effettivo. La flessibilità può essere una richiesta vincolata, con un costo crescente quando ci si allontana dal preferito.

Bisogna distinguere proprietà rigide, proprietà flessibili e priorità di intervento. Ridurre uno spazio fra note può essere preferibile a cambiare una distanza d'apertura deliberatamente scelta dall'autore, ma questa precedenza non va inventata in modo implicito.

L'ispettore potrebbe indicare:

```text
Preferred: 12 pt
Effective: 10.5 pt
Allowed range: 9–18 pt
Reason: page composition
```

### Questioni e prove

Interazione con tenuta, vedove/orfane, griglia, sezioni e figure; pagina che non entra neppure al minimo; determinismo fra cache fredda e calda; nessuna alterazione delle distanze rigide; stesso risultato in anteprima, PDF e stampa.

**Legame con il progetto:** qualità della pagina, futura ottimizzazione verticale e gestione delle richieste di collocazione.

## 6. Riquadri relazionali e modelli di pagina

### Spunto di partenza

Usare le possibilità dei frames descritte nel riepilogo della sezione 3 come riferimento per un sistema di relazioni fra aree editoriali.

### Proposta per GRIFFR

Definire aree con identità, scopo e relazioni, non soltanto quattro coordinate indipendenti:

- corpo principale;
- colonna sinistra e destra;
- fascia delle note;
- margine esterno;
- testatina e piede corrente;
- area della testata di capitolo;
- destinazioni per figure o altri flottanti.

Esempi di intenzioni:

```text
Right column width = Left column width
Inner edge of margin note = Outer edge of body + 8 mm
Bottom of body = Top of footnote area
Header aligns with body
Text flows from column A to column B
```

### Tre problemi da mantenere distinti

1. **Geometria:** dove sono i riquadri e come dipendono l'uno dall'altro.
2. **Flusso:** in quale area prosegue il contenuto quando una destinazione è piena.
3. **Composizione:** quali righe, note o figure vengono ammesse nel tentativo di pagina.

Un risolutore geometrico non risolve automaticamente la qualità dei salti pagina, il bilanciamento o l'assegnazione dei contenuti. Anche la dipendenza fra altezza delle note e spazio del corpo richiede una politica di composizione.

### Interfaccia possibile

Un editor di pagina con aree selezionabili e relazioni denominate: «Align with», «Keep distance from», «Same width as», «Continue into». Nell'interfaccia essenziale resterebbero margini e colonne; quella avanzata mostrerebbe i rapporti.

Per le pagine affacciate distinguere lato interno/esterno da sinistra/destra, numero fisico della pagina da numerazione stampata e variante di apertura da variante pari/dispari.

### Limiti e rischi

Vincoli insufficienti, incompatibili o ciclici; relazioni che cambiano dopo un trasferimento; elementi più grandi della destinazione; ordine di flusso che forma un ciclo; pagine che cambiano modello durante la composizione. Servono diagnosi che nominino oggetti e relazioni coinvolti.

Non si propone ora una migrazione generale a un risolutore di vincoli: un primo esperimento potrebbe riguardare due aree e una sola relazione verificabile.

**Legame con il progetto:** modelli di pagina, note, colonne, testate, figure e flottanti derivati.

## 7. Marcatori informativi e fatti della composizione

### Spunto di partenza

Il meccanismo `infonode` descritto nella sezione 3 suggerisce di separare un'informazione ancorata nel contenuto dal fatto geometrico che si conosce soltanto dopo la collocazione.

### Proposta per GRIFFR

Un elemento persistente potrebbe dichiarare «qui comincia questa sezione» o «questo è il bersaglio del rimando». Una composizione accolta produrrebbe poi i fatti relativi a quell'elemento: pagina, frammenti, posizione, numero stampato e contesto editoriale.

Schema concettuale:

```text
Persistent anchor
    → composition of a specific revision
    → accepted page and fragment facts
    → field, running header, reference or generated index
```

Un possibile registro dei risultati avrebbe una chiave basata sull'identità persistente e valori riferiti alla revisione della composizione. Un indice UTF-16 può restare un dettaglio dell'editor, ma non dovrebbe diventare per questo un'identità durevole nel file.

### Applicazioni

- pagina d'inizio di una sezione;
- rimando a un paragrafo o a una parola ancorata;
- titolo corrente e intervallo di contenuti presenti sulla pagina;
- sommario e indice;
- destinazioni e collegamenti nel PDF;
- spiegazione della provenienza di un campo;
- collocazione di una nota derivata da una selezione.

GRIFFR possiede già campi e navigazione PDF secondo gli appunti attuali: qui interessa una base più uniforme per estenderli.

### Cicli e rivalutazione

Un campo può cambiare larghezza e quindi influenzare la propria pagina. Occorre distinguere fatti provvisori e definitivi, dichiarare le dipendenze e scegliere una politica di stabilizzazione. Non chiamare «pagina finale» una supposizione fatta all'inizio del paragrafo.

Casi da discutere: passaggio da pagina 9 a 10, numeri romani lunghi, titolo corrente molto esteso, sezione trasferita per tenuta, riferimento cancellato, titolo modificato dopo la memorizzazione del risultato.

**Legame con il progetto:** campi, «Write Result», rimandi con etichetta e futura identità persistente degli oggetti.

## 8. Griglia delle linee di base come politica del motore

### Spunto documentato

Il pacchetto `grid` di SILE modifica il comportamento di composizione per allineare righe e spazi a una griglia; include anche un comando diagnostico che la disegna. [Codice e documentazione del pacchetto](https://github.com/sile-typesetter/sile/blob/master/packages/grid/init.lua)

### Proposta per GRIFFR

Separare una griglia visibile usata come guida da una griglia che effettivamente vincola la composizione. Per la seconda vanno esplicitati origine, passo, ambito e regole di adesione.

Possibili opzioni:

- griglia del documento o della sezione;
- griglia del singolo riquadro;
- passo legato a uno stile di corpo;
- adesione della prima linea oppure di tutte le linee;
- partecipazione o esclusione di titoli, note e didascalie;
- eventuale ritorno alla griglia dopo un elemento fuori griglia.

Una testata più alta di un multiplo del passo non dovrebbe lasciare il seguito in una posizione inspiegabile. Un font con ascendenti, discendenti o segni combinanti molto estesi richiede una politica contro le collisioni.

L'ispettore potrebbe evidenziare linea di base naturale, linea accolta e correzione applicata. Una vista con sovrapposizione della griglia aiuterebbe il controllo delle pagine affacciate.

### Prove

Corpi diversi nello stesso paragrafo, scritture con segni combinanti, righe con immagini, titoli di più righe, note, tabelle, pagine di dimensioni diverse e interazione con gli spazi elastici.

**Legame con il progetto:** lavoro tipografico indipendente già presente nel piano; dipendenze da definire prima di combinarlo con l'elasticità verticale.

## 9. Testi paralleli come flussi sincronizzati

### Spunto di partenza

I materiali `parallel`/`diglot` richiamati nella sezione 3 e la [galleria degli esempi](https://sile-typesetter.org/examples/packages/) rendono questa una pista concreta da studiare, con le cautele legate alla maturità dichiarata del pacchetto.

### Proposta per GRIFFR

Pensare a originale e traduzione come due flussi editoriali, collegati da punti di sincronizzazione, può dare più controllo di una tabella usata soltanto per allineare i paragrafi.

Possibili casi:

- greco e traduzione;
- testo latino e commento;
- due redazioni dello stesso documento;
- testo e apparato esplicativo;
- esercizi linguistici con segmenti corrispondenti.

L'unità di sincronizzazione potrebbe essere il capoverso, il versetto o un gruppo nominato dall'autore. La sincronizzazione va distinta dall'identità degli elementi: un blocco cancellato non deve far slittare tutte le associazioni successive senza una diagnosi.

### Decisioni necessarie

Cosa accade se uno dei due segmenti supera una pagina? Si divide il gruppo? Si trasferisce insieme? Quanto spazio bianco è accettabile? Le note sono per colonna o comuni? Le direzioni di scrittura possono essere diverse? L'allineamento avviene sul primo rigo, sull'ultimo o sul bordo del blocco?

Serve un modello persistente dei legami, con operazioni di divisione, fusione e spostamento annullabili. Il rendering di due colonne sincronizzate non basta a definire il comportamento dell'editor.

**Legame con il progetto:** futura generalizzazione dei corpi di testo e delle relazioni fra oggetti. È un possibile sviluppo autonomo, non una richiesta di inserirlo nella prossima tappa.

## 10. Registro comune delle operazioni e della loro interfaccia

### Spunto documentato

L'interfaccia dei pacchetti di SILE registra i comandi con la funzione, un aiuto facoltativo e informazioni sul modulo di provenienza. [API packages](https://sile-typesetter.org/lua-api/interfaces/packages.html)

### Proposta per GRIFFR

Ogni operazione del linguaggio visuale potrebbe avere un descrittore condiviso dal modello e dall'interfaccia:

```text
Stable identifier
Readable title and category
Input and output types
Parameter definitions and defaults
Evaluation phase and dependencies
Allowed effects and target kinds
Help and diagnostic messages
Serialization version
```

Questa struttura è una proposta per GRIFFR, non l'affermazione che SILE esponga già tutti questi metadati.

La libreria del compositore, gli ingressi compatibili, l'aiuto contestuale e parte della validazione potrebbero usare questi descrittori. Ciò ridurrebbe il rischio di avere un menu che offre una combinazione che il motore non sa valutare.

### Organizzazione della libreria

Categorie editoriali comprensibili: oggetti, selezioni, relazioni, misure, condizioni, calcoli, testo generato, formattazione e collocazione. Gli identificatori interni rimangono stabili mentre titoli e aiuto possono essere localizzati.

Le formule composte dell'utente potrebbero apparire nella stessa libreria con una firma dichiarata, conservando una distinzione riconoscibile rispetto alle primitive del motore.

### Apertura a estensioni

Prima di decidere se adottare plugin o un linguaggio di scripting, si può verificare il registro usando soltanto operazioni Swift già presenti. Servirebbe a separare «aggiungere un'operazione» da «scrivere ogni volta un editor differente».

Eventuali callback devono dichiarare se leggono dati, producono richieste di resa o modificano il documento in una transazione dell'editor. La facilità di estensione non giustifica effetti nascosti durante una ricomposizione.

**Legame con il progetto:** compositore ad azioni, formule riutilizzabili, tipi e futura estensione del vocabolario.

## 11. Diagnostica tipografica leggibile

### Spunto documentato

SILE espone categorie diagnostiche per compositore, interruzioni, riquadri, profilo e versioni; la CLI prevede anche backend di uscita come testo e debug. [Riferimento CLI](https://sile-typesetter.org/rust-api/src/sile/cli.rs.html)

### Proposta per GRIFFR

Trasformare le informazioni del motore in spiegazioni accessibili a chi compone il documento:

```text
The title moved to page 8 to stay with the following paragraph.
The requested space was 12 pt; the accepted space is 10 pt.
This line uses a fallback font for these characters.
This value was evaluated from natural composition, before the page variant.
The margin note could not fit without overlapping another note.
```

I testi inglesi sono esempi di possibile interfaccia, non messaggi già implementati.

### Livelli possibili

- lettura normale: solo problemi che richiedono attenzione;
- ispettore: provenienza e spiegazione dell'elemento selezionato;
- sovrapposizioni visive: riquadri, linee di base, ancoraggi, richieste e collocazioni accolte;
- rapporto tecnico esportabile: font effettivi, misure, revisioni, scelte di interruzione e dipendenze.

Un'azione nel compositore potrebbe mostrare ingresso, uscita e motivo dell'inattività. Una condizione falsa è diversa da un riferimento mancante e da una formula malformata. Le tre situazioni devono restare distinguibili.

### Confronti e regressioni

Un'uscita strutturata di GRIFFR potrebbe registrare per ogni riga pagina, intervallo del testo, coordinate, font e misure. Il confronto fra revisioni diventerebbe meno dipendente dal solo controllo di immagini o dall'estrazione del testo dal PDF.

Un eventuale confronto con SILE richiederebbe parametri equivalenti: stesso file del font, corpo, funzioni, lingua, sillabazione, larghezza e obiettivo di composizione. Differenze fra motori non sono automaticamente errori di uno dei due.

**Legame con il progetto:** ispettore della provenienza, verifica visiva, segnalazioni delle formule e affidabilità delle consegne.

## 12. Note e flottanti come contenuti con proprietario e destinazione

### Spunto di partenza

I frames e le inserzioni richiamati nel riepilogo iniziale suggeriscono un confronto con la futura generalizzazione degli stili di flottante. Non è stato verificato che il codice di SILE risolva automaticamente tutti i casi desiderati per GRIFFR.

### Proposta per GRIFFR

Distinguere esplicitamente:

1. contenuto persistente scritto dall'autore;
2. proprietario editoriale;
3. formula che individua il richiamo;
4. richiesta di collocazione;
5. destinazione disponibile nella pagina;
6. risultato della composizione.

Per il caso «quinta parola e nota a 1 cm dal bordo», il contenuto della nota deve restare conservato anche quando il paragrafo contiene soltanto quattro parole. La scatola visibile può essere sospesa; il contenuto non scompare e non va ricreato a ogni passata.

### Politiche da nominare

- nota accanto alla riga iniziale o finale del richiamo;
- comportamento della parola sillabata;
- altezza massima dell'area delle note;
- prosecuzione sulla pagina successiva;
- spazio fra note della serie;
- separatore di serie e sua proprietà;
- collisione con una nota precedente;
- contenuto troppo grande per qualsiasi destinazione;
- confini di sezione e pagine affacciate.

Gli appunti attuali di GRIFFR registrano esperimenti Alloy e questioni aperte sull'identità durante divisione e fusione dei paragrafi. Questa idea va collegata a quei risultati, non usata per aggirarli con soli indici di posizione.

**Legame con il progetto:** tappa dei flottanti derivati e successiva migrazione di note, figure e tabelle nella grammatica comune.

## 13. Laboratorio dei font e documenti di prova

### Spunto documentato

FontProof, nell'ecosistema SILE, è dedicato alle prove dei caratteri. La documentazione richiama anche comandi nativi per pangrammi e repertori di glifi. [Repository FontProof](https://github.com/sile-typesetter/fontproof)

### Proposta per GRIFFR

Generare un documento di prova dal font selezionato potrebbe essere una funzione utile sia all'autore sia allo sviluppo dell'app:

- testo scelto a più corpi e interlinee;
- confronto fra ruoli regolare, corsivo, grassetto e grassetto corsivo;
- assi variabili a valori selezionati;
- confronto fra funzioni OpenType/AAT realmente disponibili;
- campione con segni combinanti e scritture usate nel documento;
- verifica del ripiego sui font e delle sostituzioni;
- colori, estrazione del testo e ricerca nel PDF;
- repertorio con mappatura Unicode quando disponibile.

È importante distinguere repertorio dei caratteri Unicode da repertorio dei glifi: possono esistere glifi senza corrispondenza diretta a un carattere e più glifi per una sequenza. Le due viste rispondono a domande diverse.

Non si assume che FontProof supporti già ogni prova elencata: sono possibili requisiti di GRIFFR. Servono casi specifici per assi, AAT, Graphite e font a colori.

**Legame con il progetto:** supporto tipografico ampio, documenti campione e problemi già registrati sull'estrazione del testo colorato dal PDF.

## 14. Lingua, sillabazione e validazione delle quantità

### Spunto documentato

Le note di rilascio di SILE 0.15.11 descrivono correzioni dei minimi di sillabazione dipendenti dalla lingua e della lettura di misure con testo non interpretabile. Sono utili come esempi di errori reali da cui ricavare casi di verifica. [Note di rilascio](https://sile-typesetter.org/blog/release-v0.15.11/)

### Proposta per GRIFFR

Usare questi esempi per formulare contratti espliciti:

- cambiare lingua in un tratto non deve alterare i minimi di sillabazione di un altro;
- lingua del contenuto, sistema di scrittura e direzione devono essere distinguibili;
- una quantità non deve essere accettata leggendo soltanto il prefisso valido e scartando il resto;
- unità, separatore decimale e localizzazione devono avere regole note;
- divisione per zero, overflow e valori non finiti devono produrre diagnosi;
- una percentuale deve dichiarare la base a cui si riferisce.

Esempi di casi da discutere, non sintassi approvata: `12ptjunk`, `50%` senza riferimento, unità sconosciuta, misura relativa usata dove manca il contesto, testo misto con lingue che hanno regole diverse.

Queste prove possono migliorare la robustezza delle formule senza aggiungere nuovi controlli all'interfaccia ordinaria.

## 15. Componenti del motore e possibili confronti

Il repository di SILE documenta una CLI Rust con ambiente Lua e dipendenze per shaping e PDF; la combinazione preferita indicata comprende HarfBuzz e libtexpdf, con ICU per Unicode. [Repository, istruzioni di compilazione](https://github.com/sile-typesetter/sile)

### Proposte e cautele per GRIFFR

- Studiare i contratti fra input, shaping, righe, pagine e uscita può aiutare a rendere più chiari i confini interni dell'app.
- L'esistenza di un altro backend non dimostra un vantaggio nel rimpiazzare Core Text. Un confronto andrebbe fatto su problemi specifici e documenti riproducibili.
- Un esperimento di esportazione verso SILE potrebbe valutare un sottoinsieme dichiarato del documento. La fedeltà di campi, formule, stili, ancoraggi e testate andrebbe misurata, non presunta.
- Un'integrazione Lua o un motore alternativo richiederebbe uno studio distinto: distribuzione, risorse, tempi di risposta durante la scrittura, accesso ai font, ricomposizione incrementale e diagnostica.
- Prima di riutilizzare direttamente sorgenti o risorse, verificare le condizioni dei singoli componenti; questo documento non ha svolto una verifica delle licenze delle dipendenze.

Non è stata presa una decisione di integrare SILE, Lua, HarfBuzz o un nuovo backend. L'uso immediato possibile è come riferimento concettuale e come confronto su campioni delimitati.

## 16. Altri esperimenti da conservare

La [galleria di SILE](https://sile-typesetter.org/examples/) comprende esempi di forme del paragrafo calcolate e giustificazione non ordinaria; quella dei [pacchetti](https://sile-typesetter.org/examples/packages/) mostra, fra l'altro, capilettera e citazioni evidenziate.

Proposte esplorative per GRIFFR:

- forma del paragrafo come funzione della riga o di un'area occupata;
- testo che evita una sagoma, con una politica chiara di ricomposizione;
- capolettera come elemento misurato e collegato alle prime righe;
- schemi riutilizzabili di citazione con segni, filetti e attribuzione;
- testate composte da parti che leggono contenuti editoriali senza duplicarli;
- adattamento a una larghezza scelta per piccoli elementi di titolazione, con limiti leggibili dall'autore.

Sono idee da esaminare dopo aver stabilizzato identità, relazioni e misure. Una forma spettacolare nel PDF non equivale a un oggetto agevolmente selezionabile, modificabile e annullabile in un word processor.

## 17. Rapporto con le tappe attuali

| Spunto | Area di GRIFFR interessata | Domanda preliminare |
|---|---|---|
| Misure contestuali | Formule e proprietà | Qual è il contesto di valutazione? |
| Spazi elastici | Composizione della pagina | Quali distanze possono cambiare e con quale costo? |
| Riquadri relazionali | Pagine, colonne, note, figure | Quali vincoli e quali flussi sono ammessi? |
| Marcatori e fatti accolti | Campi e rimandi | Quale identità persiste nel documento? |
| Griglia | Tipografia e pagine affacciate | Quali elementi partecipano alla stessa griglia? |
| Testi paralleli | Più corpi e relazioni | Come si conservano i legami durante la scrittura? |
| Registro delle operazioni | Compositore visuale | Quale descrizione comune genera UI e controlli? |
| Diagnostica | Ispettore e verifica | Come si spiega una scelta del motore? |
| Contenuti migranti | Flottanti derivati e note | Chi possiede il contenuto quando manca il bersaglio? |
| Laboratorio font | Font, campioni e PDF | Che cosa si vuole misurare e confrontare? |
| Contratti linguistici | Lingue, sillabazione, parser | Quali stati devono restare isolati? |
| Modi dell'interlinea (21.1) | Stili di paragrafo | Quale modo per righe con corpi misti? |
| Regole per lingua (21.2) | Lingue e formule contestuali | Regola del motore o formula dello stile? |
| Capolettera (21.3) | Stili di paragrafo, testate | Dentro la cornice del testo, come oggetto misurato? |
| Note a margine impilate (21.4) | Flottanti a margine | Spostare da sé o segnalare? |
| Corpo dall'altezza della x (21.5) | Font e ruoli | Per tratto, per ruolo o per ripiego? |
| Ripieghi scelti (21.6) | Font | Lista per documento o per stile? |
| Cornici statiche (21.7) | Pagine e flottanti | Che cosa non affidare alle cornici? |
| Stabilità della composizione (21.8) | Formato e motore | Quale versione del motore si registra? |
| Struttura del PDF (21.9) | PDF | Quali oggetti marcare, con quali tag? |
| Ruby (21.10) | Testo e annotazioni | Serve per le glosse? |

Le dipendenze qui indicate sono tecniche, non un ordine di realizzazione approvato. In particolare, gli appunti attuali dicono che un primo sistema di campi e testate è già stato realizzato. Le idee SILE devono rafforzarlo dove serve.

Il confronto con [IDEE-DA-LOUT.md](IDEE-DA-LOUT.md) può aiutare a individuare convergenze: destinazioni per contenuti, rimandi, misure editoriali e scelte di pagina. Prima di unire proposte simili occorre confrontarne il significato preciso; parole uguali non garantiscono modelli equivalenti.

## 18. Piccoli esperimenti possibili, senza impegnare il progetto

Questi sono candidati per valutare le idee, non attività già autorizzate da questo file.

1. **Una misura relativa persistente.** Un rientro pari a 2 em, usato con due corpi diversi, deve mostrare espressione e risultati corretti senza perdere la relazione al salvataggio.
2. **Uno spazio flessibile.** Un titolo con spazio preferito e minimo dichiarati deve spiegare la correzione accolta e mantenere tenuta e progressione delle pagine.
3. **Un fatto accolto.** Un marcatore ancorato a una sezione deve restituire la pagina corretta dopo un trasferimento causato dalla tenuta.
4. **Due aree con una relazione.** Il corpo e una fascia di note condividono un confine; aumentare la fascia deve lasciare il resto della geometria spiegabile.
5. **Una griglia visibile ed effettiva.** Il motore e la sovrapposizione devono concordare sulle linee accolte, anche dopo una testata.
6. **Una diagnosi leggibile.** Selezionare un titolo spostato deve spiegare quale richiesta ha determinato la collocazione.
7. **Due flussi sincronizzati.** Un campione corto di originale e traduzione permette di discutere le politiche prima di progettare un editor completo.
8. **Un campione di font riproducibile.** Stessi contenuti e risorse dichiarate, con verifica distinta di resa e testo estratto dal PDF.

Per ogni esperimento conviene registrare ingresso, versione del documento, font e risorse, risultato atteso, risultato osservato e limiti. Una prova tecnica riuscita non sostituisce la valutazione dell'interazione nella finestra reale.

## 19. Questioni aperte da portare nella progettazione

- È utile un solo linguaggio per formule degli stili e catene dei campi? Quali tipi e dipendenze mancano oggi?
- Quali fatti della composizione possono essere letti prima della collocazione e quali soltanto dopo?
- Quali operazioni sono pure e quali producono richieste o modifiche persistenti?
- Come conservare l'intenzione di una misura relativa quando cambia il contesto?
- Come nominare e spiegare i conflitti fra vincoli, priorità, griglia e spazi elastici?
- Quale contratto lega un contenuto persistente alla sua occorrenza visibile, soprattutto se il bersaglio scompare?
- Come mantenere identità e riferimenti in incolla, divisione, fusione e spostamento?
- Quali aspetti del registro delle operazioni devono essere versionati nel file?
- Quali dati minimi rendono riproducibile un problema tipografico?
- Quali nuove funzioni meritano controlli dedicati e quali devono restare nella modalità avanzata?

## 20. Fonti e punti da approfondire

### Fonti principali consultate

- [Sito di SILE](https://sile-typesetter.org/)
- [Presentazione del progetto](https://sile-typesetter.org/what-is-sile/)
- [Repository SILE](https://github.com/sile-typesetter/sile)
- [Manuale 0.15.12](https://sile-typesetter.org/manual/sile-0.15.12.pdf)
- [Indice dell'API Lua](https://sile-typesetter.org/lua-api/)
- [Measurement](https://sile-typesetter.org/lua-api/types/measurement.html)
- [Length](https://sile-typesetter.org/lua-api/types/length.html)
- [Interfaccia dei pacchetti](https://sile-typesetter.org/lua-api/interfaces/packages.html)
- [Interfaccia dei typesetter](https://sile-typesetter.org/lua-api/interfaces/typesetters.html)
- [CLI Rust e opzioni diagnostiche](https://sile-typesetter.org/rust-api/src/sile/cli.rs.html)
- [Pacchetto grid, codice e documentazione](https://github.com/sile-typesetter/sile/blob/master/packages/grid/init.lua)
- [Esempi generali](https://sile-typesetter.org/examples/)
- [Esempi dei pacchetti](https://sile-typesetter.org/examples/packages/)
- [FontProof](https://github.com/sile-typesetter/fontproof)
- [Note di rilascio 0.15.11](https://sile-typesetter.org/blog/release-v0.15.11/)

Per la sezione 21, i capitoli del manuale 0.15.12: 5.4.1 dropcaps, 5.10.2 font-fallback, 5.11 grid e linespacing, 5.14.4 retrograde, 5.15 frametricks, twoside, masters, break-firstfit e balanced-frames, 5.16.10–11 pdf e pdfstructure, 3 (`\font`, unità e `adjust`), 8.5 lingue, 13.2 note a fianco. L'elenco dei pacchetti viene dalla cartella [packages](https://github.com/sile-typesetter/sile/tree/master/packages) e dal sorgente [c05-packages.sil](https://github.com/sile-typesetter/sile/blob/master/documentation/c05-packages.sil).

### Parti da esaminare meglio prima di riutilizzare algoritmi

Frames e risoluzione dei vincoli; costi e terminazione del page builder; inserzioni; sincronizzazione dei flussi; trattamento delle misure nelle cache; metadati che attraversano le fasi; risorse linguistiche; API effettive delle versioni scelte; condizioni delle dipendenze.

Questa raccolta conserva le piste emerse dalla ricerca. La selezione delle idee e l'eventuale specifica di implementazione verranno dopo.

## 21. Altre idee dal manuale · aggiunte il 9 novembre

Seconda lettura del manuale 0.15.12 (capitoli dei pacchetti, delle lingue e delle note a fianco), confrontata con il codice di GRIFFR del 9 novembre. Dove si dice che GRIFFR non ha una cosa, è stato cercato nei sorgenti, non provato nell'app.

Il manuale dà a ogni pacchetto un grado di maturità: buona, «usabile con limiti», sperimentale. Va tenuto presente: `grid` è usabile con limiti, `linespacing`, `parallel`, `balanced-frames`, `frametricks`, `cropmarks` e `indexer` sono sperimentali.

### 21.1 Modi dell'interlinea

**Spunto documentato.** Il comportamento predefinito di SILE è quello di TeX: le linee di base stanno a una distanza fissa (`baselineskip`), ma se fra la discendente di una riga e l'ascendente della seguente restano meno di 2 pt (`lineskip`) si allontanano. Il pacchetto `linespacing` aggiunge altri modi:

- **fixed:** distanza fissa da linea di base a linea di base, in em (relativa al corpo) o in punti;
- **fit-glyph:** le righe si toccano davvero, la discendente più bassa contro l'ascendente più alta, più uno spazio scelto (`extra-space`);
- **fit-font:** come fit-glyph, ma con l'altezza e la profondità massime dei font della riga, come un lingotto di piombo;
- **css:** come nei browser: la distanza è `line-height`, e la differenza con l'altezza reale si divide sopra e sotto la riga.

**In GRIFFR.** Gli stili hanno l'interlinea fissa e quella proporzionale (`lineSpacing`, `lineHeightMultiple`).

**Proposta.** Un modo «a contatto più uno spazio» per i paragrafi con corpi misti, formule, simboli grandi o segni combinanti impilati, dove un'interlinea fissa fa scontrare le righe e una proporzionale le allarga tutte. Va deciso il rapporto con la griglia (sezione 8): con la griglia accesa questi modi non valgono, o valgono e poi si arrotonda?

### 21.2 Regole tipografiche per lingua

**Spunto documentato** (manuale, 8.5):

- **francese:** spazio fine indivisibile prima di `; ! ?`, spazio da parola prima dei due punti, spazi dentro le virgolette basse; le tre misure sono parametri (`languages.fr.thinspace`, `colonspace`, `guillspace`);
- **croato, ceco, polacco, portoghese, slovacco, spagnolo:** a capo su un trattino già presente, il trattino si ripete all'inizio della riga seguente;
- **turco:** si può andare a capo dopo un apostrofo, senza trattino (o, a scelta, sostituendo l'apostrofo con il trattino);
- **amarico:** a capo dopo lo spazio e il punto etiopici; due stili di spaziatura attorno alla punteggiatura;
- **esperanto:** due modi di scrivere il suffisso degli ordinali (15ª o 15-a);
- **francese e turco:** nel dialogo lo spazio dopo la lineetta iniziale resta fisso;
- **giapponese e cinese:** regole di a capo (*kinsoku*) e spaziatura fra i caratteri secondo il documento W3C *Requirements for Japanese Text Layout*.

Altre regole: gli spazi indivisibili sono elastici, salvo `languages.fixedNbsp`; dalla 0.15.11 i minimi di sillabazione dipendono dalla lingua.

**In GRIFFR.** Non sono state trovate regole di questo tipo nel motore. Le «regole tipografiche per lingua» sono nell'elenco del lavoro tipografico indipendente.

**Proposta.** Sono un elenco pronto di casi. Alcune sono composizione (il trattino ripetuto, l'a capo dopo l'apostrofo) e stanno nel motore; altre sono spazi (il francese) e potrebbero essere formule degli stili legate alla lingua del tratto, visibili e modificabili. Da decidere: lo spazio francese si aggiunge in composizione o si scrive nel testo? Nel primo caso l'autore non lo vede e non lo può togliere in un punto; nel secondo, cambiare lingua lascia spazi sbagliati.

### 21.3 Capolettera

**Spunto documentato** (`dropcaps`, maturità buona): quante righe occupa (`lines`, 3 per difetto), scala rispetto alla prima riga (`scale`), unione alla prima riga (`join`) con la distanza dal testo delle righe seguenti (`standoff`, uno spazio per difetto), colore, spostamenti fini (`raise`, `shift`), funzioni del font. Le capitali con la coda sotto la linea di base, come Q e J, per difetto si rimpiccioliscono per restare nelle righe; con `strict=false` si misura solo l'altezza.

**In GRIFFR.** Nessun capolettera.

**Proposta.** Una parte dello stile di paragrafo, accanto alla testata, con le stesse opzioni. Va con la sezione 21.7: il capolettera si compone dentro la cornice del testo, scostando le prime righe, e non dividendo la cornice.

### 21.4 Note a margine che si impilano

**Spunto documentato** (manuale, 13.2): in un progetto con due tipi di note a fianco, i segni nel margine non si sovrappongono mai, mentre i rimandi nella colonna interna, frequenti, «si impilano»: stanno almeno all'altezza del loro versetto e scendono se le note precedenti occupano il posto.

**In GRIFFR.** Le note a margine che si sovrappongono o escono dallo specchio si segnalano (`marginConflicts`) e restano dove sono, da sistemare a mano.

**Proposta.** Una politica per serie di note: «segnala» (com'è ora) o «impila» (scende sotto la precedente, e se esce dallo specchio si segnala). Si collega alle politiche della sezione 12.

### 21.5 Corpo dato dall'altezza della x

**Spunto documentato.** `\font` accetta `adjust=ex-height` o `adjust=cap-height` al posto del corpo: il font prende la dimensione per cui la sua altezza della x (o delle maiuscole) è uguale a quella del testo, con un moltiplicatore facoltativo.

**In GRIFFR.** Nei sorgenti del motore l'altezza della x non compare; compare solo nell'interfaccia.

**Proposta.** Utile quando in una riga si mescolano font diversi (latino con greco o cirillico, un font di ripiego, un ruolo con un altro font). Potrebbe stare nei ruoli dei font o essere un'unità delle misure contestuali (sezione 4): «corpo = 1 ex del testo».

### 21.6 Ripieghi scelti dall'autore

**Spunto documentato** (`font-fallback`): SILE non sceglie da sé un font per i caratteri mancanti; mostra il glifo `.notdef`, a meno che l'autore non dia una lista ordinata di font da provare (`\font:add-fallback`).

**In GRIFFR.** Il ripiego lo sceglie macOS; GRIFFR lo rileva e lo mostra (`FontFallback`).

**Proposta.** Una lista di ripieghi per documento o per stile, provata prima di quella di sistema. Con la sezione 21.5, ogni ripiego potrebbe avere l'altezza della x pareggiata.

### 21.7 Cornici statiche, non cornici al volo

**Spunto documentato.** Il manuale avverte, a proposito di `frametricks`, che dividere e spostare le cornici durante la composizione per figure, capilettera e simili non si è rivelata una buona soluzione: «crea più problemi di quanti ne risolva», e InDesign e simili gestiscono figure, capilettera e tabelle dentro la cornice del testo.

**Proposta.** È un limite da tenere per la sezione 6 e per le idee 1 e 5 di [IDEE-DA-LOUT.md](IDEE-DA-LOUT.md). Le cornici e i posti descrivono la pagina; figure, capilettera, tabelle e testo che gira attorno si risolvono dentro la cornice, scostando le righe.

Collegati: `masters` (insiemi di cornici fra cui si sceglie, anche per una sola pagina) e `twoside`, il cui `\open-spread` apre su una pagina dispari e toglie testatine e numeri dalle pagine lasciate bianche.

### 21.8 Stabilità della composizione fra versioni

**Spunto documentato** (`retrograde`, maturità buona): quando un valore predefinito o un comportamento del motore cambia, i documenti vecchi si ricompongono diversamente. Il pacchetto rimette, per quanto possibile, i valori di una versione indicata (`target=v0.15.12`), senza cambiare il documento.

**Proposta.** È un problema diverso dalla compatibilità del formato, che GRIFFR ha tolto l'8 novembre: lo stesso file, letto senza errori, può dare pagine diverse con un motore nuovo. Si potrebbe scrivere nel file la versione del motore che l'ha composto e, quando cambia un comportamento che sposta le righe, segnalarlo all'apertura, o conservare il comportamento vecchio finché l'autore non accetta il nuovo.

### 21.9 Struttura del PDF e accessibilità

**Spunto documentato.** `pdf` (maturità: usabile con limiti) ha `\pdf:destination`, `\pdf:link` (con bordo, stile del bordo, colore), `\pdf:bookmark`, `\pdf:metadata`. `pdfstructure` crea l'albero della struttura del PDF; con `\pdf:structure` nelle classi si può arrivare a un PDF/UA.

**In GRIFFR.** Collegamenti, segnalibri ed etichette delle pagine ci sono dal 9 novembre (`PDFNavigation`); l'albero della struttura marca solo i paragrafi (`P`).

**Proposta.** Marcare titoli con il loro livello (`H1`…), note (`Note`), figure con un testo alternativo, tabelle e celle, voci d'elenco. È il passo seguente per un PDF accessibile; il testo alternativo delle figure sarebbe un dato nuovo del documento.

### 21.10 Ruby e scritture dell'Asia orientale

**Spunto documentato.** `ruby` mette un testo piccolo sopra la parola, o accanto nella scrittura verticale (`\ruby[reading=れいわ]{令和}`). `hanmenkyoshi` costruisce la griglia dei caratteri giapponese (*hanmen*); `tate` dà le cornici verticali, il latino ruotato e il *tate-chu-yoko* (testo orizzontale in una casella della griglia verticale). `break-firstfit` va a capo senza ottimizzare, come si fa nel giapponese su griglia. `boustrophedon` alterna la direzione delle righe.

**In GRIFFR.** Nulla di questo. Il compositore ottimale rinuncia alle righe da destra a sinistra (`LineBreaker`), e la composizione ottimale RTL è già nell'elenco.

**Proposta.** Il meccanismo del ruby (un testo legato a un tratto e posato sopra) potrebbe servire anche fuori dal giapponese: pronunce, traslitterazioni, brevi glosse sopra le parole. Le glosse interlineari a più righe allineate parola per parola, però, sono un problema diverso, che SILE non tratta. Il resto è lontano dalle priorità attuali.

### 21.11 Elenco completo dei pacchetti, per riferimento

Dalla cartella `packages` del repository: autodoc, background, balanced-frames, bibtex (bibliografie con CSL), bidi, boustrophedon, break-firstfit, chapterverse, chordmode, color, color-fonts, complex-spaces, converters, counters, cropmarks, date, debug, dropcaps, features, folio, font-fallback, footnotes, frametricks, grid, gutenberg, hanmenkyoshi, ifattop, image, indexer (dalla 0.15.10: intervalli di pagine, collegamenti, ordinamento per lingua), infonode, inputfilter, insertions, leaders, linespacing, lists, lorem, masters, math, pagebuilder-bestfit, pandoc, parallel, pdf, pdfstructure, pullquote, raiselower, rebox, retrograde, rotate, ruby, rules, scalebox, simpletable, specimen, svg, tableofcontents, tate, textcase, twoside, unichar, url, verbatim, xmltricks.

Dalla raccolta esterna resilient.sile: ingressi Markdown e Djot, un sistema di stili unificato, una scelta di gabbie di pagina «antiche o moderne». I nomi delle gabbie non si sono trovati nelle pagine lette (la guida è un PDF su Google Drive, non letto).
