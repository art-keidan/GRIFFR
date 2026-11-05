# Piano per trasformare gli stili in formule

4 novembre 2026

Il risultato atteso è aprire **Testo**, **Titolo 1**, **Enfasi** o un altro stile e trovarne nella bacheca tutte le formule, comprese famiglia, corpo, rientri e comportamenti. Modificare la pill del corpo cambia la stessa definizione che l'utente modifica dall'interfaccia essenziale. Ogni formula conserva identità, argomenti, ordine e provenienza attraverso salvataggio, importazione e annullamento.

Il lavoro procede nel fork. La [riformulazione degli stili attuali](STILI-COME-FORMULE.md) è il riferimento per gli esempi. Il catalogo e il codice del primo compositore forniscono una base da ampliare.

## 1 · Fissare il significato di Imposta e Aggiungi

Definire per ogni proprietà il tipo del valore e le operazioni ammesse.

| Espressione | Stato in ingresso | Stato in uscita |
|---|---|---|
| [Imposta] [Font] [Grassetto] | Corsivo | Grassetto |
| [Aggiungi] [Font] [Grassetto] | Corsivo | Grassetto corsivo |
| [Imposta] [Spazio prima] [6 pt] | 12 pt | 6 pt |
| [Aggiungi] [Spazio prima] [6 pt] | 12 pt | 18 pt |

Imposta e Aggiungi sono predicati con effetto. Font e Spazio prima sono argomenti. La richiesta di grassetto conserva la famiglia e passa dal risolutore dei ruoli già esistente. Una famiglia variabile può realizzarla attraverso un asse. L'assenza della variante richiesta deve avere una diagnosi coerente col comportamento dei font.

Per decorazioni e funzioni tipografiche la composizione va definita per tipo. Per proprietà come la lingua, il menu offre inizialmente Imposta. La forza della regola rispetto ai valori locali è un'altra dimensione.

Una nuova valutazione riparte dagli ingressi della catena. Applicare la formula aggiuntiva cento volte deve produrre lo stesso risultato osservabile di una valutazione sul medesimo ingresso.

**Risultato verificabile.** Tabella dei contratti delle proprietà e prove del motore sulle quattro combinazioni dei ruoli tondo, corsivo, nero e nero corsivo, su spazi, unità e rivalutazione.

## 2 · Introdurre la rappresentazione unica delle formule

Aggiungere una struttura tipizzata per oggetto iniziale, operazione, argomenti, condizione e destinazione. Ogni nodo e ogni formula hanno identità stabile. Le definizioni riutilizzabili conservano parametri e riferimenti. Ogni stile possiede le proprie formule e un riferimento alla base ereditata.

Il primo vocabolario eseguibile copre Questo oggetto, Caratteri contenuti, valori costanti, lettura di proprietà, Imposta, Aggiungi ed eredità. I nuovi predicati entrano poi attraverso le medesime firme tipizzate. Le scelte delle pills vengono ricavate dal tipo dell'ingresso e dal catalogo registrato.

Nella transizione StyleValues può restare come risultato risolto per i componenti che già lo consumano. La definizione autorevole dello stile passa progressivamente alle formule. Gli adattatori devono esplicitare quali espressioni riescono a rappresentare.

**Risultato verificabile.** Lo stile Forte è espresso con Aggiungi Font Grassetto e può essere valutato su un carattere corsivo. Testo è espresso con formule per famiglia, corpo e giustificazione.

## 3 · Portare nella bacheca gli stili reali

La bacheca deve elencare gli stili del documento e aprire le rispettive formule. Una scheda rappresenta uno stile, con riferimento alla base e righe di pills per ogni dichiarazione. Le selezioni condivise rimangono definizioni richiamabili.

Per la prima consegna visibile, migrare insieme i predefiniti di paragrafo, parola e carattere e le relative proprietà costanti. L'autore deve poter cambiare **Imposta** in **Aggiungi** per una proprietà compatibile e vedere il risultato, salvare e riaprire.

Mostrare per ogni formula il valore letto in ingresso e quello prodotto. Il campione serve per sperimentare. Il comando Applica registra la definizione nel documento e l'ispettore conferma il valore effettivo sulla selezione.

**Risultato verificabile.** Una parola corsiva diventa nera con Imposta e nero corsiva con Aggiungi. Citazione permette di sostituire rientro 24 pt con una formula che aggiunge 6 pt al rientro ricevuto.

## 4 · Collegare tutti i controlli alla stessa definizione

Adattare l'editor degli stili, l'ispettore, l'aggiornamento dello stile dalla selezione, duplicazione, rinomina e importazione. Un controllo di valore costante modifica il nodo pertinente. Se la proprietà è calcolata, mostra formula, risultato e accesso alla bacheca. Sostituirla con una costante deve essere un'azione esplicita.

Distinguere i comandi che modificano lo stile da quelli che producono formattazione locale sul testo. La logica riutilizzabile rimane nello stile. Una proprietà manuale conserva la propria provenienza e la precedenza prevista.

Alcune funzioni attuali eliminano una dichiarazione quando coincide col valore ereditato. Con le formule serve distinguere la dichiarazione esplicita dall'eredità, perché un successivo cambio della base può dare esiti diversi. Eliminare una formula usa il comando Eredita o Rimuovi, con la sua conseguenza visibile.

**Risultato verificabile.** Cambiare il corpo nella scheda Stili aggiorna la pill corrispondente. Cambiare la stessa pill aggiorna il controllo. Annulla e Ripeti ripristinano definizione e resa insieme.

## 5 · Trasferire condizioni, relazioni e comportamenti

Portare nel modello di formule la variante a inizio pagina, le condizioni numeriche e le ricerche oggi in TextRule. Conservare la fase di valutazione delle regole storiche quando si leggono i documenti precedenti.

Separare le formule di resa dalle azioni di scrittura. L'apertura di una sezione appartiene all'assegnazione dello stile. L'eventuale stile dopo Invio appartiene alla creazione del capoverso. Le informazioni sulla pagina derivano da un tentativo di collocazione o da una composizione accolta, con dipendenze dichiarate.

Le regole storiche trasversali vanno rappresentate con lo stesso linguaggio, conservandone ambito e precedenze. La scelta di collocarle visivamente in una sezione comune della bacheca evita di duplicarle arbitrariamente in più stili.

**Risultato verificabile.** La formula di apertura pagina e il titolo spostato dalla tenuta mantengono la quota corretta. Le prime parole seguono il testo dopo una modifica. Assegnare uno stile che apre un capitolo crea una sola sezione.

## 6 · Rendere uniformi anche tabelle e flottanti

Migrare le dichiarazioni degli stili di tabella, i valori delle celle e gli stili di flottante con le firme specifiche necessarie. Collocazione, tenuta e numerazione sono richieste al compositore, da risolvere secondo le politiche del motore.

Separatore e spazi di una serie di note hanno come proprietario il blocco della serie. La numerazione legge lo stato della Lista. Il modello deve conservare questi ambiti per evitare separatori ripetuti o contatori incrementati durante una rivalutazione.

**Risultato verificabile.** Griglia, Tre filetti, Nota a piè di pagina e Figura sono ispezionabili come formule e mantengono il risultato dei campioni precedenti, comprese le eccezioni locali.

## 7 · Collegare Posizione e Scrivi risultato

Riutilizzare le formule per i campi. Un campo conserva la propria posizione ancorata, la formula e lo stile del risultato. Scrivi risultato aggiorna l'occorrenza esistente.

La prima prova è **Posizione → Pagina contenente → Numero formattato → Scrivi risultato Qui**. Seguono titolo e numero della sezione corrente. L'eventuale testo che cambia misura durante la composizione deve passare per il meccanismo di aggiornamento e terminazione previsto.

**Risultato verificabile.** Aggiungere testo prima del campo ne cambia la pagina e aggiorna il numero. Salvare, riaprire e ricomporre conserva un campo solo e la formula originale.

## 8 · Migrare il formato e i documenti in ogni incremento

Definire un formato versionato per nodi, firme delle operazioni, unità, identità e riferimenti. La prima versione che scrive formule complete richiede una versione successiva alla 3 attuale. Ogni costrutto deve essere leggibile prima che il suo controllo sia disponibile all'utente.

La conversione dei vecchi stili deve preservare le dichiarazioni effettive e la loro precedenza. Nel vecchio modello il corsivo o il nero omesso mantiene il tratto ricevuto. Per un tratto attivo la traduzione può usare Aggiungi. Un tratto esplicitamente disattivato richiede una composizione che rimuova quel tratto conservando l'altro. Il predicato Sottrai ora fornisce questa operazione; la conversione automatica dei tratti disattivati resta da integrare rispettando le precedenze storiche. Serve a coprire anche gli stili personalizzati, oltre ai predefiniti.

Attenzione particolare alla risoluzione dell'eredità. Una dichiarazione del figlio che sostituisce il ruolo completo deve sostituire la precedente dichiarazione sulla stessa proprietà. Gli effetti aggiuntivi si compongono nell'ordine dichiarato. Il convertitore deve conservare i casi in cui il vecchio modello risolve prima le proprietà ereditate e poi le applica al testo.

Conservare la protezione dell'originale al primo incremento di versione. Per l'incolla fra documenti, importare le dipendenze delle formule e risolvere identità e nomi in conflitto. Un eventuale formato precedente si può produrre solo se la definizione è rappresentabile integralmente.

**Risultato verificabile.** Andata e ritorno su tutti i predefiniti e su stili personalizzati con falsi espliciti, zero, liste, assi variabili e valori locali. L'importazione di una formula condivisa mantiene i suoi riferimenti.

## 9 · Confrontare, consolidare e rimuovere gli adattatori superati

Prima del cambiamento del risolutore, acquisire un riferimento dai campioni e dalle prove del fork nella revisione corrente. Confrontare testo, valori effettivi, font e glifi, numero di pagine, coordinate dei titoli, note e tabelle. Registrare i problemi preesistenti dell'ambiente.

Conservare il confronto tra valutazione storica e valutazione da formule sui documenti convertiti finché copre le proprietà migrate. Le cache devono dipendere dalle formule e dai loro riferimenti. Il risultato deve coincidere a cache fredda, calda e dopo il cambio della base.

Quando tutti gli ingressi scrivono formule e tutte le uscite ne leggono i risultati, eliminare le vie di definizione duplicate. Le rappresentazioni risolte che servono a Core Text e al compositore possono continuare a esistere come prodotti della valutazione.

**Risultato verificabile.** Tutti gli stili si possono ispezionare nella bacheca e modificare dai controlli previsti. Una modifica produce lo stesso risultato a schermo, alla riapertura e nel PDF.

## Ordine operativo e prima consegna

Le fasi 1 e 2 preparano il meccanismo. La prima consegna utilizzabile deve completare insieme una parte della 3, della 4 e della 8, con verifica della 9. Comprende gli stili Testo, Forte, Enfasi e Citazione, Imposta e Aggiungi, pills modificabili, i controlli di font e rientro, Annulla e file riapribili. Si passa poi agli altri predefiniti e alle proprietà rimanenti.

Il formato e la compatibilità accompagnano ogni incremento. Le fasi 5, 6 e 7 estendono l'insieme comune delle formule a tutte le famiglie già individuate. Ogni consegna termina con una funzione osservabile e un campione che permette all'autore di provarla.

Le scelte ancora da affinare riguardano la conversione dei tratti disattivati tramite Sottrai e le formule con effetti sullo stesso argomento. I casi di prova ne permettono una proposta concreta durante l'implementazione.

## Avanzamento del 4 novembre 2026

Prima tappa completata per il nucleo di Imposta e Aggiungi. I [contratti e i risultati delle prove](PREDICATI-IMPOSTA-AGGIUNGI.md) documentano font, lunghezze e proprietà discrete, oltre al perimetro ancora da collegare alla struttura salvata delle formule. La tappa successiva è la rappresentazione comune delle definizioni.

Seconda tappa implementata per le formule con argomenti costanti, collegate al risolutore, all'eredità e al file v4. Il [resoconto della struttura](STRUTTURA-FORMULE-STILI.md) descrive integrazione e limiti. La prossima consegna visibile è l'esposizione degli stili reali e delle loro formule nella bacheca.

Terza tappa implementata per gli stili reali di paragrafo, parola e carattere: elenco nella bacheca, conversione delle proprietà costanti supportate, pills, ingressi e risultati, anteprima, applicazione al testo e Annulla. Il [resoconto e il campione](STILI-REALI-BACHECA.md) descrivono anche le dichiarazioni avanzate ancora conservate nel modello compatibile. Le nuove proprietà richiedono il formato 5. La tappa successiva è collegare tutti i controlli alla medesima definizione, rendendo esplicita la sostituzione delle formule con valori costanti.

Aggiunto il predicato [Sottrai](SOTTRAI.md), disponibile per font e misure nella bacheca, con persistenza nel formato 6.

Quarta tappa: i controlli ordinari scrivono le formule supportate e mostrano i calcoli. La sostituzione con un valore fisso è esplicita; la bacheca segue i cambi esterni senza perdere le bozze. Il [resoconto dei controlli](CONTROLLI-E-FORMULE.md) descrive interfacce, aggiornamento dalla selezione, formato 7 per la faccia precisa e verifiche. La tappa successiva porta condizioni, relazioni e comportamenti nello stesso modello.

Quinta tappa implementata per condizioni, destinatari e comportamenti dichiarativi. La bacheca distingue le fasi, espone le regole storiche e collega variante di inizio pagina, tenuta, apertura di sezione e stile dopo Invio alle formule. Il [resoconto e il campione](CONDIZIONI-E-COMPORTAMENTI.md) descrivono il formato 8 e i limiti delle combinazioni iniziali. La prossima tappa riguarda tabelle e flottanti.
