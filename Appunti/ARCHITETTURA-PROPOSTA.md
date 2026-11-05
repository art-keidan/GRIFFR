# GRIFFR · Proposta di architettura degli stili

Tappa 3 · Bozza per la discussione · 4 novembre 2026

Un autore dovrebbe poter aprire lo stile *Titolo di capitolo* e scegliere «Quando il titolo apre la pagina, lascia 3 cm dal margine superiore». Nell'interfaccia essenziale gli basta applicare quello stile. Nel compositore visuale può vedere da dove viene la distanza, sostituire la condizione o riusarla per un altro stile.

Propongo di conservare nel documento **l'intenzione editoriale**. Il motore calcola per ogni occorrenza **il trattamento tipografico**. L'editor registra separatamente **le azioni di scrittura**. Questa divisione permette di distinguere due richieste che, sulla pagina, potrebbero apparire identiche. «Premendo Invio crea un capoverso di stile Corpo» è un atto dell'autore, da salvare e poter annullare. «Il capoverso dopo un titolo ha rientro zero» è una relazione da rivalutare quando cambia il vicino.

La logica appartiene agli stili, come richiesto nella [visione](VISIONE.md). Le decisioni tecniche e i valori predefiniti suggeriti qui sono proposte. La fotografia del programma da cui si parte è nella [ricognizione archiviata](archivio/ARCHITETTURA-ATTUALE.md).

## Chi possiede che cosa

| Elemento | Che cosa conserva o produce | Quanto dura |
|---|---|---|
| Documento | Contenuto scritto, struttura, assegnazioni di stile, valori manuali e definizioni con nome | Attraverso salvataggio e riapertura |
| Definizione di stile | Proprietà di base, varianti, effetti su bersagli collegati e azioni di scrittura. Può richiamare operazioni condivise | Nel documento, ereditabile |
| Occorrenza | Il capoverso, la sezione o il flottante concreto cui si riferisce una valutazione. Fornisce contenuto, vicini e ruolo | Finché esiste quell'elemento |
| Selezione calcolata | Una parola, un intervallo o una raccolta individuati sul testo di una certa revisione | Fino a una modifica degli ingressi |
| Composizione | Frammenti di capoverso, righe, pagine, misure e oggetti generati per la resa | Per una specifica impaginazione |
| Editor | Selezione, evento in corso e transazione che registra una modifica, compreso Annulla | Durante la scrittura |

Terrei il deposito vivo come autorità sul testo durante la modifica. Un adattatore deve permettere di consultarlo per capoversi, sezioni e intervalli, offrendo la stessa semantica al documento appena caricato. Mantenere contemporaneamente un secondo albero editabile obbligherebbe a riconciliare ogni incolla, spostamento e annullamento. La composizione riceve invece una revisione coerente di contenuto e definizioni. Un risultato calcolato su una revisione superata si scarta. Questo disegno si innesta sul ponte fra albero e testo già in uso. [DocumentStore](../Sources/Typesetting/DocumentStore.swift) · [AttributedBridge](../Sources/Typesetting/AttributedBridge.swift)

**Identità.** Propongo identificativi salvabili per i capoversi ai quali occorre riferirsi e per le definizioni condivise. Rinominare uno stile deve conservare i collegamenti. «Quinta parola» si salva come ricerca relativa al capoverso. «Questa parola» richiede invece un'ancora salvata con estremi su confini di grafema e una convenzione per gli inserimenti ai bordi. Se scompare tutto il testo ancorato, l'ispettore deve poter segnalare il riferimento perduto. Spostare conserva l'identità, duplicare ne crea una nuova e Annulla ripristina i riferimenti. Le regole attuali di divisione e fusione del deposito sono il punto di partenza per stabilire quale capoverso erediti l'identità.

## Come l'autore costruisce un comportamento

Una regola dello stile specifica **da quale oggetto partire, quale bersaglio raggiungere, quando applicarsi e quale effetto produrre**. Il punto di partenza implicito è l'occorrenza che usa lo stile. Ogni «predicato», nel senso scelto per GRIFFR, dichiara l'oggetto che lo espone, i parametri, il tipo del risultato e il momento in cui quel risultato è disponibile. Una condizione è soltanto uno degli usi possibili.

| Espressione illustrativa | Risultato utilizzabile |
|---|---|
| Sul capoverso, conta fino alla quinta parola | Una parola, oppure nessun risultato |
| Dalla parola, prendi il testo | Testo leggibile, anche per una didascalia |
| Dal capoverso, prendi il successivo nello stesso corpo | Un capoverso, oppure nessun risultato |
| Sul capoverso, misura il numero di parole | Un intero, confrontabile con una soglia |
| Dalla riga di richiamo, prendi la pagina | La pagina di quella riga nella composizione corrente |

Il compositore presenta solo operazioni compatibili con l'uscita precedente. Distingue parole da testo, numeri da lunghezze, oggetti singoli da raccolte. L'autore può dare un nome a un'espressione, esporne un parametro e richiamarla da un'altra definizione. Per esempio *Parola del richiamo(N)* restituisce una parola e può essere condivisa da due stili di nota. Le definizioni con nome formano un insieme senza richiami circolari. Gli effetti stanno alla fine dell'espressione e dichiarano il loro bersaglio. Così un'operazione riusata due volte per trovare una parola non inserisce due note.

Un bersaglio mancante è un esito normale della ricerca. Con quattro parole la regola per la quinta resta inattiva e l'ispettore ne mostra il motivo. Un riferimento cancellato e un'espressione mal formata sono invece diagnosi distinte. Una definizione incompatibile va corretta prima dell'attivazione. Questi contratti delimitano un primo linguaggio visuale finito, estensibile con nuove primitive o con combinazioni di quelle esistenti.

## Quando si valuta una regola

1. **Scrittura.** Alla pressione di Invio, l'editor distingue la creazione di un capoverso dalle altre funzioni del tasto, come uscire da una voce vuota di elenco. Se viene creato un capoverso a fine titolo, l'azione dello stile gli assegna lo stile Corpo nella stessa transazione di Invio. Una successiva ripaginazione non ripete l'azione.
2. **Contenuto e struttura.** Su una revisione stabile si risolvono ereditarietà, parole, ruoli e relazioni fra vicini. Una dichiarazione può applicare una proprietà a un intervallo o al capoverso successivo. Il suo contributo scompare quando cessa la relazione. I selettori leggono gli stili assegnati dall'autore, così un effetto visivo su un vicino non attiva a cascata nuovi stili.
3. **Collocazione sulla pagina.** Il compositore valuta le varianti che dipendono dal posto in cui sta provando a deporre un elemento. Se il titolo, per effetto di «tieni col seguente», viene spostato su una nuova pagina, elimina il tentativo precedente e lo misura nel nuovo contesto. Il risultato conserva quale variante ha determinato la posizione scelta.
4. **Lettura del risultato.** L'ispettore può interrogare l'impaginato definitivo. Un effetto puramente grafico può leggerne le misure. Se una regola vuole cambiare gli a capo basandosi sul numero di righe, propongo di offrirle la misura dichiarata «prima della variante», coerente con le regole naturali esistenti. Il compilatore delle espressioni segnala le dipendenze dalla geometria finale che renderebbero indeterminato il loro stesso ingresso. Le passate specializzate per campi e note restano responsabilità del motore. [PageLayout](../Sources/Typesetting/PageLayout.swift)

Per il titolo propongo di definire «apre la pagina» rispetto alla **prima riga del capoverso e al primo posto nel flusso principale**. Una testatina corrente non occupa quel posto. Una continuazione dalla pagina precedente lo occupa, ma non costituisce un nuovo inizio del capoverso. La distanza si misura dal margine superiore dello specchio di testo al sommo della prima riga e sostituisce lo spazio prima. Se neppure sulla pagina vuota entrano distanza e prima riga, il compositore deve terminare con una diagnosi e una resa utilizzabile. Un possibile ripiego è ridurre la distanza per quel titolo e mostrarne il valore effettivo. È una scelta editoriale da provare.

## Conflitti e spiegazione

Per ogni proprietà il risolutore raccoglie i contributi applicabili e conserva l'origine del vincitore. Propongo quest'ordine crescente di forza.

1. Predefiniti del documento, stili ereditati e valori dello stile assegnato.
2. Effetti ordinari di uno stile o di una sua variante.
3. Valore locale dato a mano.
4. Vincolo che l'autore dello stile ha dichiarato esplicitamente obbligatorio.

Fra effetti dello stesso grado propongo di preferire la dichiarazione del bersaglio a quella ricevuta da un vicino, poi una priorità dichiarata e infine l'ordine salvato delle regole. Due obblighi incompatibili devono comparire insieme nell'ispettore, anche se il criterio di spareggio permette di comporre. La precedenza si decide per proprietà. Un vincolo sul rientro lascia all'autore la scelta del font. Un valore manuale temporaneamente coperto resta recuperabile quando si rimuove il vincolo.

L'ispettore dovrebbe poter dire «Rientro 0 mm, imposto da Titolo di capitolo sul capoverso seguente. Rientro locale 5 mm». Per la distanza d'apertura dovrebbe mostrare anche quale fatto è stato letto e in quale fase. Schermo e PDF devono consumare i medesimi valori risolti. Il programma distingue già fra valore locale, stile, regola e documento. [Inspection](../Sources/Typesetting/Inspection.swift)

## Testate e flottanti

Per una testata nello spirito di *memoir* propongo una **composizione associata allo stile del titolo**. L'autore scrive il titolo una volta. La testata legge testo e numero di capitolo e dispone parti nominate, per esempio numero, filetto e titolo. Ogni parte ha uno stile e relazioni semplici di flusso, allineamento e distanza. Un titolo su tre righe aumenta l'altezza del blocco e sposta il corpo che segue. La sezione conserva il titolo semantico per indice, mappa e intestazione corrente. La soluzione alternativa, una serie di capoversi ordinari inseriti nel testo, renderebbe ambiguo quale costituisca il titolo quando si rinomina o si sposta il capitolo.

Per la quinta parola, lo stile può produrre un **flottante derivato**. Il bersaglio testuale si determina prima della paginazione. La riga che contiene il richiamo stabilisce pagina e quota verticale. Il bordo esterno del riquadro dista 1 cm dal bordo fisico esterno del foglio, specchiato sulle pagine affacciate. Il contenuto comprende un capoverso con stile X. Questa richiesta distingue il bordo del foglio dal margine del testo, due riferimenti grafici che la GUI deve nominare separatamente.

Se il testo della nota è scritto dall'autore, si salva nel documento e si lega alla regola e al capoverso proprietario. Se deriva da un campo, si salva la sua espressione. Ripetere la composizione produce una sola occorrenza per regola, proprietario e ruolo. Se il bersaglio temporaneamente manca, il testo scritto resta disponibile. Per la prima versione proporrei di segnalare le collisioni nel margine, in continuità con le note attuali. Va deciso se occorra anche spostarle automaticamente.

## Collegamento con il programma

| Responsabilità proposta | Punto di innesto e vincolo |
|---|---|
| Definizioni e persistenza | Estendere il foglio stili con operazioni nominate e regole possedute dagli stili. Conservare unità, riferimenti, ordine e forza dei contributi. Il lettore XML è rigoroso. Serve una versione esplicita per i nuovi costrutti e una lettura dei vecchi file che ne preservi il risultato. [DocumentFormat](../Sources/Typesetting/DocumentFormat.swift) |
| Valutazione | Separare la lettura di oggetti e fatti dalla produzione di valori tipografici. Riutilizzare l'estrazione delle parole e i fatti già disponibili, documentando per ciascuno unità, ambito e fase. [Rules](../Sources/Typesetting/Rules.swift) · [DynamicFacts](../Sources/Typesetting/DynamicFacts.swift) |
| Composizione e costo | Far entrare nelle chiavi delle cache tutti gli ingressi che modificano la misura. Un cambio nel capoverso precedente può invalidare il successivo. Come prima garanzia usare la ricomposizione completa con riuso dei risultati validi. L'aggiornamento selettivo si può misurare in seguito. |
| Interfacce | L'essenziale applica stili pronti. L'avanzata modifica proprietà e varianti comuni. Il compositore apre la stessa definizione, controlla i collegamenti fra operazioni e anticipa l'effetto su un esempio. Un controllo semplice che copre solo parte di una definizione deve preservare il resto. |
| Regole esistenti | Leggere le regole del documento secondo il loro ordine, ambito ed eccezioni attuali. Convertirle in definizioni di stile solo dove si può dimostrare equivalenza, incluse quelle che oggi valgono trasversalmente su più stili. |

## Scelte da verificare con l'autore

| Situazione concreta | Preferenza proposta | Alternativa e conseguenza |
|---|---|---|
| Inserisco una parola prima della quinta | La nota segue la nuova quinta parola se la regola cerca per posizione. | Un comando «ancora a questa parola» conserva il bersaglio originale e deve gestirne la cancellazione. |
| Cambio a mano il rientro imposto da un titolo | Il vincolo esplicito prevale e l'ispettore mostra il valore locale sospeso. | Un'eccezione autorizzata sul singolo capoverso rende il vincolo derogabile. |
| Una figura occupa la cima della pagina prima del titolo | Contare la figura se occupa spazio nel flusso principale. | «Primo capoverso di testo» può essere vero anche sotto la figura. Le due domande possono meritare nomi distinti. |
| Premo Invio a metà titolo | Riservare inizialmente «stile successivo» a Invio in fondo. | Applicarlo anche alla divisione trasforma la seconda metà in testo del corpo. |
| La testata richiede una disposizione insolita | Partire da flusso, allineamenti, misure e riferimenti ai bordi. | Vincoli grafici liberi ampliano il repertorio, ma richiedono anche regole per risolvere misure incompatibili. |

La tappa 4 potrà giudicare il disegno da risultati osservabili. Un titolo portato alla pagina seguente deve ricevere una sola volta la distanza corretta. Spezzare e ricomporre il documento deve conservare una sola nota con il testo scritto dall'autore. Cambiare la lunghezza del titolo deve far scorrere la testata. Salvare, riaprire e annullare una modifica deve preservare sia il contenuto sia la spiegazione della formattazione. Questi scenari distinguono le scelte editoriali ancora aperte dai requisiti di correttezza del motore.

## Precisazioni emerse nella tappa 4

Per una testata composta, la distanza d'apertura si riferisce per default al bordo del blocco intero. Il riferimento alla prima riga descritto sopra vale per il titolo semplice. Un'operazione sui vicini specifica il flusso e i confini strutturali che può attraversare. Per una nota generata, la definizione distingue il proprietario del testo salvato dalla parola e dalla riga che determinano la sua collocazione corrente. Le sequenze di modifica, le misure attese e le preferenze ancora aperte sono negli [scenari di verifica archiviati](archivio/SCENARI-DI-VERIFICA.md).
