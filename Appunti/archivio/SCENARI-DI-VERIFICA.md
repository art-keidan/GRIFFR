# GRIFFR · Prove di tenuta del modello degli stili

Tappa 4 · 4 novembre 2026 · Verifica su carta della [proposta architetturale](ARCHITETTURA-PROPOSTA.md).

Il disegno permette di descrivere tutti e quattro i casi guida. I tentativi di metterlo in difficoltà fanno emergere tre contratti da precisare prima del catalogo delle operazioni. La distanza di apertura ha bisogno di un bersaglio geometrico preciso. Il capoverso «successivo» ha bisogno di un ambito di lettura. Una nota generata con testo scritto a mano ha bisogno di un proprietario durevole anche mentre è invisibile.

Le misure che seguono sono dati di prova scelti per rendere i risultati controllabili. Gli esiti sono previsioni del modello proposto. I rimandi al codice identificano i comportamenti esistenti con cui confrontare una futura implementazione.

## 1 · Il titolo entra, il capoverso seguente lo porta sulla pagina nuova

**Preparazione.** Un titolo in una sezione continua misura 12 mm, ha 4 mm di spazio prima, zero dopo e richiede di restare con la prima riga del capoverso seguente, alta 5 mm. La pagina 1 ha 18 mm disponibili. Lo stile prescrive 30 mm dal margine superiore dello specchio quando il titolo apre il flusso principale. La pagina 2 ha uno specchio alto 180 mm.

| Tentativo | Decisione attesa | Riscontro |
|---|---|---|
| Pagina 1, dopo il testo già composto | Il titolo solo entra. Con la prima riga successiva occorrono 4 + 12 + 5 = 21 mm. Si ritira il tentativo. | Sulla pagina 1 rimane solo il testo precedente. Anche eventuali segni, note e motivazioni del tentativo vengono ritirati. |
| Pagina 2, primo posto del corpo | Si rivaluta lo stile nel nuovo posto. La distanza di 30 mm sostituisce lo spazio prima. | Il bordo superiore del blocco cade a 30 mm dall'inizio dello specchio. Con margine del foglio di 25 mm, la quota fisica è 55 mm. Il blocco finisce a 67 mm e lì comincia la prima riga del corpo. |
| Si accorcia il testo precedente, liberando altri 4 mm sulla pagina 1 | Con 22 mm disponibili l'intero gruppo entra. | Il titolo torna sulla pagina 1 con 4 mm di spazio prima. Annulla ripristina il titolo sulla pagina 2 a 55 mm dal bordo del foglio. |

Salvando dopo lo spostamento e riaprendo con la stessa carta e gli stessi font si deve ritrovare la stessa quota. Nel file servono la distanza, la condizione e il vincolo. L'indice di pagina ottenuto durante la prova dura una sola composizione. L'ispettore deve spiegare separatamente perché il titolo ha cambiato pagina e perché lì parte più in basso. La prova di confronto parte da due capacità già distinte nel motore, tenuta della catena e distanza d'apertura strutturale. [KeepWithNextTests](../Tests/TypesettingTests/KeepWithNextTests.swift) · [SectionTests](../Tests/TypesettingTests/SectionTests.swift)

**Controprova.** Con soli 40 mm utili anche la pagina vuota è troppo corta per 30 + 12 + 5. Propongo di conservare titolo e prima riga insieme riducendo la distanza effettiva a 23 mm, e mostrarne la ragione. Se il gruppo supera la pagina anche a distanza zero, occorre allentare la tenuta e consumare contenuto a ogni passo. L'ordine dei sacrifici è una preferenza editoriale. La terminazione del tentativo è un requisito.

**Correzione al disegno.** «Primo posto del flusso» va calcolato sul contenuto già collocato prima del candidato. Una testatina corrente lascia libero quel posto. Una figura in flusso o la continuazione di un capoverso lo occupa. «Primo capoverso di testo» è una domanda diversa e potrebbe restituire vero sotto una figura. La variante va misurata di nuovo dopo ogni trasferimento e applicata una volta al blocco accolto. Nel codice attuale la previsione di inizio pagina, il controllo di apertura di sequenza e il recupero del tentativo di tenuta avvengono in punti distinti. [PageLayout](../Sources/Typesetting/PageLayout.swift)

## 2 · Invio dopo un titolo e rientro imposto al vicino

**Preparazione.** Lo stile Titolo prevede due comportamenti. Invio in fondo crea un capoverso Corpo. Il primo capoverso immediatamente seguente riceve inoltre rientro di prima riga zero, con forza obbligatoria. Corpo ha per impostazione propria 5 mm.

1. Premendo Invio si ottiene un solo capoverso nuovo. La sua assegnazione a Corpo si salva. La regola del titolo spiega il rientro zero finché il nuovo capoverso è adiacente. Un solo Annulla immediato rimuove la creazione, Ripeti la riproduce una volta.
2. Si assegna al capoverso il rientro locale di 8 mm. Resta visibile zero. Si sposta il titolo altrove e ricompare 8 mm. Spostando indietro il titolo si ripristina zero. Il testo continua a usare Corpo in tutti i passaggi.
3. Si salva mentre il vincolo copre gli 8 mm. Alla riapertura l'ispettore deve poter mostrare sia lo zero imposto sia gli 8 mm conservati. Cambiare formato della carta non genera capoversi e non modifica l'adiacenza logica.
4. Con il titolo a fine sezione si inserisce una sottosezione, oppure si frappone una tabella prima del Corpo. Una scansione del testo piatto potrebbe raggiungere il titolo interno o la prima cella. Occorre distinguere il successore strutturale dalla prossima posizione nell'editor.

**Correzione al disegno.** Per questo esempio «successivo» significa *primo blocco del corpo della medesima sezione dopo il titolo, se è un capoverso*. Una tabella interrompe l'adiacenza. Un'altra operazione potrebbe cercare il primo capoverso saltando le tabelle. La GUI deve rendere riconoscibile la differenza. Propongo di attivare l'azione di scrittura solo sull'evento «creato capoverso con Invio in fondo». Incollare due paragrafi, premere Maiuscole+Invio o uscire da un elenco vuoto sono eventi distinguibili. Il percorso editor attuale già tratta alcuni comandi in funzione del contesto. [Comandi delle pagine](../Sources/WordProcessor/EditorWindowController+Pagine.swift)

## 3 · Testata nello spirito di memoir

**Preparazione.** Il capitolo 9 ha un titolo scritto una sola volta. Il modello di testata mostra il numero sul lato esterno, poi un filetto, poi il titolo. Il numero occupa una fascia alta 12 mm, seguono 3 mm, un filetto di 0,5 mm e altri 2,5 mm. Ciascuna riga del titolo occupa 6 mm. Dopo la testata restano 8 mm prima del corpo. Le misure si riferiscono a rettangoli di composizione, con spazio prima e dopo delle singole parti posto a zero.

| Modifica | Risultato osservabile |
|---|---|
| Titolo di una riga | Dalla sommità della testata al primo capoverso del corpo si misurano 12 + 3 + 0,5 + 2,5 + 6 + 8 = 32 mm. |
| Il titolo si estende a tre righe | Il corpo si abbassa di 12 mm, fino a 44 mm. Il titolo resta uno nella mappa e il campo «titolo corrente» legge il testo aggiornato. |
| Si inserisce un capitolo prima del 9 e la testata passa su una pagina pari | La stessa sezione diventa capitolo 10. Il numero prende la nuova larghezza naturale e si allinea al bordo esterno sinistro su pagine affacciate. L'autore continua a modificare un unico titolo. |
| Si salva, si riapre e si cambia lo stile della parte numero | Le parti vengono ricomposte dal modello salvato. Il numero appare una sola volta, anche se il titolo di capitolo usa già una Lista per la numerazione. |

**Controprova decisiva.** Sullo stesso titolo si attiva la distanza di 30 mm del caso 1. Se «titolo» indica la prima riga di testo, i 18 mm di numero e ornamenti salgono sopra la quota richiesta. Se indica la testata intera, la testata inizia a 30 mm e il testo a 48 mm. Le due letture erano possibili nella proposta.

**Correzione al disegno.** Propongo come riferimento predefinito il bordo superiore del blocco di apertura. Per un titolo semplice coincide con il bordo superiore della prima riga composta. Per un titolo composto è il bordo della testata. Chi vuole allineare il testo a una quota sceglie esplicitamente la parte «titolo». Il modello deve inoltre poter usare il numero della Lista una sola volta, sostituendo la resa ordinaria del segno con la parte «numero». Lo spostamento del testo e la sua provenienza si verificano sia sulla pagina sia in PDF. [Modello della sezione](../Sources/Typesetting/Document.swift) · [Composizione di segni e pagine](../Sources/Typesetting/PageLayout.swift)

## 4 · Quinta parola, una nota nel margine a 1 cm dal bordo

**Preparazione.** Nel capoverso «alfa beta gamma delta epsilon zeta» l'operazione restituisce *epsilon*. Un unico flottante contiene un capoverso in stile X con il testo «Confronta il manoscritto B», scritto dall'autore. Su carta larga 210 mm, con margini affacciati abbastanza larghi, il bordo destro del riquadro su pagina dispari è a x = 200 mm. Su pagina pari il bordo sinistro è a x = 10 mm. La prima linea di base della nota si allinea a quella del richiamo.

| Azione | Esito atteso |
|---|---|
| Si inserisce «zero» all'inizio | La quinta parola diventa *delta*. La stessa nota, con lo stesso testo, segue il nuovo bersaglio. |
| Si cambia la larghezza di pagina e il richiamo passa dalla dispari alla pari | La nota segue la pagina e la riga del richiamo e cambia lato. Due ricomposizioni identiche danno una sola nota. |
| Il capoverso viene ridotto alle prime quattro parole | La ricerca restituisce vuoto. Il flottante perde la sua collocazione. Il testo scritto a mano resta accessibile dal capoverso proprietario. |
| Si salva con quattro parole, si riapre e se ne aggiunge una quinta | Ricompare una sola nota, ancora in stile X, con il testo originale. Annullando quest'ultima aggiunta si torna allo stato sospeso. |
| Si sposta il capoverso oppure se ne fa una copia | Lo spostamento conserva il proprietario. Per una duplicazione esplicita propongo una copia indipendente della nota e nuovi identificativi. |

**Correzione al disegno.** Servono due livelli distinguibili. Il contenuto scritto si salva sotto una chiave durevole composta da proprietario, regola e parte. La scatola visibile nasce in ciascuna composizione, quando esiste un bersaglio. Legare il testo all'intervallo di *epsilon* farebbe perdere l'associazione già al primo inserimento. Inoltre «la riga della parola» può comprendere due righe se la parola è sillabata. Per una nota appesa *dopo* la parola propongo la riga dell'ultimo grafema, con affinità verso il carattere precedente al confine. Il trattino aggiunto componendo resta estraneo alla ricerca. La collocazione nel margine e la segnalazione delle collisioni esistono già in forma specializzata. [Righe e note marginali](../Sources/Typesetting/PageLayout.swift) · [Modello del flottante](../Sources/Typesetting/Document.swift)

## Esito e passaggio al catalogo

Il modello distingue correttamente l'azione di Invio dalla formattazione dipendente dai vicini e consente di separare il titolo editoriale dalla sua resa. Le tre precisazioni emerse entrano come requisiti per la tappa 5. Ogni operazione che attraversa il documento deve dichiarare **quale flusso percorre**. Ogni misura deve dichiarare **quali bordi o frammenti mette in relazione**. Ogni effetto con contenuto editabile deve dichiarare **chi conserva quel contenuto se il bersaglio manca**.

Restano preferenze editoriali la priorità fra distanza e tenuta quando la pagina è troppo corta, il trattamento delle figure prima del titolo e la copia delle note alla duplicazione. I valori scelti qui sono sufficienti per costruire i primi esempi visuali. La verifica eseguibile richiederà un prototipo con il nuovo risolutore. Le prove del progetto attuale costituiscono il confronto di partenza per regole, tenuta e salvataggio. [Regole](../Tests/TypesettingTests/RuleTests.swift) · [Tenuta](../Tests/TypesettingTests/KeepWithNextTests.swift) · [Formato](../Tests/TypesettingTests/DocumentFormatTests.swift)
