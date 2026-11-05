# Visione: stili, oggetti e composizione

Bozza di lavoro del 4 novembre 2026, ricavata dalla conversazione con l'ideatore. Raccoglie la direzione del progetto e gli esempi discussi; non è ancora una specifica tecnica né una descrizione delle funzioni già realizzate. Le questioni aperte sono indicate in fondo.

## L'idea

GRIFFR aspira a essere un word processor tipograficamente versatile, controllabile attraverso un'interfaccia grafica, senza obbligare a scrivere codice. Deve essere semplice da usare per scrivere un documento ordinario e, allo stesso tempo, permettere a chi lo desidera di costruire comportamenti e composizioni sofisticate.

Il documento è una struttura di elementi che possono avere proprietà, esporsi informazioni e partecipare a relazioni. Il fine è dare all'autore un controllo tipografico concreto: per esempio, definire una volta l'aspetto e il comportamento dei titoli di capitolo e riutilizzarli in tutto il documento.

## Tre livelli di interfaccia

- **Essenziale:** il minimo necessario per scrivere e impaginare, con buoni valori predefiniti e controlli comprensibili. La semplicità non deve comportare una povertà tipografica: l'aspirazione è gestire una gamma molto ampia di font e delle loro possibilità.
- **Avanzato:** accesso a più proprietà, stili e controlli tipografici, senza dover necessariamente costruire espressioni.
- **Compositore di stili:** un ambiente di programmazione visuale, entro limiti ragionevoli, per combinare operazioni e costruire comportamenti riutilizzabili. Non si punta, per ora, a un linguaggio di programmazione generale.

L'idea da verificare nella progettazione è che i tre livelli operino sullo stesso documento, presentandone progressivamente le possibilità. I dettagli del passaggio fra livelli e dell'uso di uno stile complesso nell'interfaccia essenziale restano da progettare.

## Che cosa si chiede agli stili

La logica descritta qui è concentrata **negli stili**, non nella formattazione occasionale data a mano. Rispetto agli stili di paragrafo tradizionali, uno stile dovrebbe poter comprendere:

- **Proprietà condizionate:** un valore cambia quando una condizione è soddisfatta; le condizioni possono essere varie e combinabili.
- **Proprietà contestuali:** il comportamento dipende, per esempio, dalla posizione del paragrafo, dai suoi vicini o dalla sezione che lo contiene.
- **Azioni passive**, nel linguaggio usato nella conversazione: comportamenti associati a un evento dell'editor, come fare in modo che premendo Invio il nuovo paragrafo adotti uno stile stabilito.
- **Azioni attive:** effetti che uno stile può imporre ad altri elementi, comprese formattazioni applicate in modo vincolante. Destinatari e precedenze sono da definire.
- **Informazioni disponibili ad altri stili:** dati ricchi sul contenuto, sulla struttura e sulla composizione, dal numero di caratteri e parole alla geometria e alla collocazione.

Lo stile è una definizione riutilizzabile; le informazioni concrete, come il numero di parole o la posizione sulla pagina, riguardano il singolo elemento a cui si applica. Questa distinzione è una proposta interpretativa da verificare nel progetto del modello.

La direzione estende principi già familiari nei word processor: «tieni con il successivo», controllo di vedove e orfane e stile del paragrafo successivo sono esempi di stili che influenzano composizione e comportamento, oltre all'aspetto.

## Operazioni componibili: i «predicati»

Nella terminologia dell'ideatore, un **predicato** è un'operazione esposta da un oggetto, alla quale si possono fornire parametri e che restituisce un risultato. Il termine è vicino a «metodo» o «operazione»; non indica necessariamente un'affermazione vera o falsa.

Esempio concettuale: applicando al paragrafo l'operazione «contare» con i parametri «parola» e «5», si ottiene la quinta parola. Il nome e la forma precisi dell'operazione sono da definire; l'esempio esprime il comportamento desiderato.

L'output di un'operazione può essere usato in un'altra espressione. L'obiettivo è partire da un **numero limitato di operazioni fondamentali**, poi consentire di comporle, nominare le combinazioni e riutilizzarle, in modo paragonabile all'idea di costruire macro LaTeX a partire da strumenti esistenti. La scelta del vocabolario iniziale è parte del lavoro futuro.

Occorre anche distinguere, nella progettazione, la lettura di informazioni o la selezione di elementi dagli effetti che cambiano una proprietà o il documento. Non è ancora deciso come tale distinzione apparirà all'utente.

## Esempi che il progetto deve saper discutere

### Titolo all'inizio della pagina

Uno stile di titolo prevede un'impostazione specifica quando il paragrafo che lo usa è il primo della pagina: per esempio, far partire il titolo di capitolo più in basso rispetto al margine superiore. La questione generale è consentire a uno stile di reagire alla posizione effettiva, non soltanto offrire un'opzione speciale per i capitoli.

GRIFFR possiede già una distanza d'apertura per il paragrafo che apre una sequenza di pagine e una regola relativa al primo paragrafo di pagina. Le due cose non equivalgono ancora, da sole, a una soluzione generale per qualsiasi proprietà contestuale. Lo stato preciso del codice sarà verificato nella tappa 2.

### Testata di capitolo nello spirito di `memoir`

Definire una volta uno stile di capitolo che disponga numero, eventuale etichetta, titolo, filetti e spazi con formattazioni e relazioni proprie. La testata dovrebbe adattarsi, per esempio, alla lunghezza del titolo e alla numerazione del capitolo. I `chapterstyle` della classe LaTeX `memoir` sono il riferimento tipografico, non un obbligo di riprodurne il codice o tutte le possibilità nella prima versione.

Come rappresentare la testata e quanto debba essere libera la sua composizione sono decisioni aperte.

### Un paragrafo e il successivo

Uno stile di titolo può stabilire che il paragrafo creato premendo Invio adotti lo stile «Testo». Una relazione distinta potrebbe influenzare la formattazione di un paragrafo che segue un titolo. Il primo esempio riguarda un evento di scrittura; il secondo una relazione tra elementi. I dettagli di applicazione e precedenza vanno definiti.

### Quinta parola e flottante

Individuare la parola numero N di un paragrafo e associarle un flottante nel margine, a una distanza dal bordo pagina stabilita, con contenuto e stile scelti. È un caso di prova per la componibilità delle operazioni, le relazioni fra testo e pagina e la capacità di collocare oggetti.

Non è ancora deciso se in questo esempio il bersaglio debba rimanere sempre la parola in posizione N o seguire la parola individuata originariamente, né se il flottante debba essere generato automaticamente o creato una volta sola.

## Questioni aperte per il disegno

1. Quali oggetti e quali informazioni devono essere disponibili nel primo insieme utile? Come rappresentare quelli che emergono dalla composizione, come righe e pagine?
2. Quali operazioni primitive servono davvero per esprimere i casi d'uso prioritari? Come si definiscono, nominano, parametrizzano e riutilizzano le combinazioni?
3. Quali espressioni vengono rivalutate automaticamente e quali comportamenti si attivano soltanto in risposta a un evento o a un comando?
4. Quali effetti possono agire su altri elementi? Che cosa significa «imporre rigidamente» e quale regola prevale in caso di conflitto con altri stili o con la formattazione manuale?
5. Come si valutano condizioni che dipendono dalla composizione quando il loro effetto può cambiare la composizione stessa? Come si spiegano conflitti e risultati all'utente?
6. Che cosa succede quando un'operazione non trova il risultato richiesto o quando un elemento collegato viene modificato o cancellato?
7. Come si conserva il comportamento nel formato del documento e come si evolve il formato preservando i documenti esistenti?
8. Quali controlli devono essere disponibili in ciascuno dei tre livelli di interfaccia? Come si presentano e modificano gli stili complessi nei livelli più semplici?
9. Quali tecnologie e funzionalità dei font sono già supportate, e quali richiedono ulteriori sviluppi? Il supporto universale è un'aspirazione, non una capacità già verificata.

## Prossimo passo

La visione resta il riferimento stabile del progetto. Per lo stato corrente e il lavoro residuo si veda il [riepilogo aggiornato](RIASSUNTO-RESIDUO.md); il piano storico è nell'[archivio](archivio/PIANO.md).
