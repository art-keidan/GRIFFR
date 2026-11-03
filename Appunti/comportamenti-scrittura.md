# Che cosa sa fare la scrittura

L'elenco di ciò che l'editor sa fare, voce per voce, con la prova che lo controlla. Serve quando si cambia il codice
dell'editor: dice che cosa deve continuare a funzionare e dove guardare. Si aggiorna a ogni funzione nuova.
Stato del 2 novembre 2026.

Colonna **Prova**:
- un codice («S1», «SZ4»): la prova in `Tests/WordProcessorTests` il cui titolo comincia con quel codice; queste prove
  guidano la finestra dell'editor intera, tasto per tasto. Alcuni codici sono usati in due file diversi (per esempio
  M1, M2, T1, R1–R3, G4–G6): si cercano con il titolo, `grep -rn '"M1 ·' Tests/WordProcessorTests`;
- **StoreEditingTests**: le prove senza codice in `Tests/WordProcessorTests/StoreEditingTests.swift` (deposito e
  struttura delle sezioni, guidate dall'editor);
- **motore**: la controllano solo le prove del motore (`Tests/TypesettingTests`);
- **a schermo**: nessuna prova automatica, si controlla a occhio.

## Scrittura, cancellazione, cursore

| # | Comportamento | Prova |
|---|---|---|
| S1 | Un carattere entra al cursore, che avanza; una selezione viene sostituita da ciò che si scrive. | S1 |
| S2 | Cancella indietro, avanti, parola indietro e avanti, fino a inizio o fine di riga o paragrafo; con una selezione si cancella la selezione. Quanto cancellare lo decide il motore (rispetta note e lettere composte). | S2 |
| S3 | A capo spezza il paragrafo; cancellare all'inizio di un paragrafo lo unisce al precedente. | S3 |
| S4 | Frecce, parola per parola, inizio e fine di riga, paragrafo e documento, Pagina su e giù; con Maiuscole si estende la selezione. | S4 |
| S5 | Si scrive con gli attributi del carattere che precede il cursore (font, stili, lingua). | S5 |
| S6 | Fuori da un elenco Tab scrive una tabulazione; Maiuscole+Invio (o Ctrl+Invio) va a capo dentro lo stesso paragrafo; Invio da solo, o con Comando, no. | S6 (due prove) |
| S7 | Seleziona tutto. | S7 |
| S8 | Clic, doppio clic (parola), triplo clic (paragrafo, con le note che richiama); trascinando dopo un doppio o triplo clic la selezione cresce di una parola o di un paragrafo alla volta. Una selezione non passa dal corpo a una nota. | a schermo |
| M4 | Nel margine sinistro un clic seleziona la riga con l'a capo; trascinando si prendono più righe. | M4 |
| S9 | Comandi rari della tastiera: scambia due lettere, maiuscole, minuscole e iniziali maiuscole della parola (gli altri suonano); si annullano. | S9 |
| K1 | Cancella indietro nelle scritture indiane e del Sud-Est asiatico (dal devanagari al khmer) toglie un carattere per volta: dopo «मे» prima la vocale, poi la consonante, anche col cursore in mezzo a una lettera, con Core Text e con Graphite. Il cursore si muove per lettere intere; Cancella verso destra toglie la lettera intera. Nelle altre scritture l'accento va con la sua lettera, l'emoji è intera. | K1; motore |
| S10 | Vista › Mostra caratteri nascosti (⇧⌘I): spazio ·, spazio non separabile °, tabulazione →, a capo nel paragrafo ↵, fine paragrafo ¶, riquadro intorno ai richiami di nota; solo a schermo; la scelta vale per tutte le finestre e si ricorda. | motore; a schermo |

## Annullamento

| # | Comportamento | Prova |
|---|---|---|
| U1 | Una parola scritta di seguito si annulla in un passo; spostare il cursore apre un passo nuovo; Ripeti rifà. | U1 |
| U2 | Scrivere e cancellare sono passi diversi. | U2 |
| U3 | Ogni comando (stile, elenco, nota, funzioni del font, assi, ispettore, Liste…) è un passo con il suo nome nel menu Modifica; il trascinamento di un cursore degli assi è un passo solo. | T1, C1 (in parte); a schermo |
| U4 | Dopo un annullamento il cursore resta nel paragrafo giusto, e l'elenco con cui si scrive è quello del paragrafo. | a schermo |
| U5 | Il documento risulta modificato dopo un tasto, e torna pulito annullando. | U5 |
| U6 | Dopo Annulla o Ripeti di un testo scritto o cancellato il cursore va alla fine del punto cambiato, senza selezione. | U6 |
| U7 | Annulla di un comando (stile, ispettore, sezioni, tabelle, Taglia, Incolla…) rimette la selezione di prima del comando; Ripeti quella lasciata dal comando. In una tabella il cursore torna nella cella dov'era. | U7, U8 |

## Note e altri flottanti

| # | Comportamento | Prova |
|---|---|---|
| N1 | Inserisci › Nota (⌥⌘F) mette il richiamo e porta il cursore nel testo della nota; Esc torna al corpo, dopo il richiamo. | N1 |
| N2 | Cancellare indietro subito dopo un richiamo toglie tutta la nota (si annulla intera); all'inizio del testo della nota non toglie nulla. | N2 |
| N3 | In una nota si incolla solo il testo: una nota non ne contiene altre. | N3 |
| N4 | Una nota non entra in un'altra nota (il comando suona). Un testo di nota rimasto senza richiamo torna testo del corpo. | a schermo; motore |
| N5 | Una nota di un'altra serie (stile di flottante) si inserisce dal menu e sta nel blocco della sua serie. | N5 |
| N6 | Una nota di chiusura si inserisce, ci si scrive alla fine del documento, Esc torna al testo. | N6 |
| N7 | Una nota a margine si inserisce e ci si scrive, nel margine accanto alla riga. | N7 |
| N9 | All'inizio di un paragrafo, davanti al richiamo di una nota, si scrive con l'aspetto del corpo. | N9 |
| I1 | Un'immagine nella riga si cancella con un tasto, si annulla, si copia e si incolla come immagine; le sue misure con un doppio clic o il tasto destro. | I1; M2 (menu) |

## Elenchi, Liste, stili, regole

| # | Comportamento | Prova |
|---|---|---|
| L1 | Elenco: a capo crea una voce; a capo in una voce vuota esce di un livello o chiude l'elenco; cancellare all'inizio di una voce toglie il segno; vale anche alla fine del testo. | L1 |
| L2 | Tab e Maiusc-Tab cambiano il livello delle voci senza nome; nelle Liste con un nome no. | L2 |
| L3 | Formato › Elenco; nel righello Lista e «Liste…» (scheda Liste); domanda quando una Lista finisce i segni. | a schermo |
| T1 | Lo stile di paragrafo si applica dalla barra e dà anche la sua Lista; annullando tornano stile e Lista di prima. | T1 |
| T2 | Stili di parola e di carattere (menu «Stile» del Ribbon), Nuovo stile, Aggiorna lo stile (conserva la Lista). «Nuovo stile…» dal monitor incorpora solo l'aggiunta scelta, la toglie dal testo e conserva le altre. | M3; S5 (in parte); motore |
| T3 | Ispettore: valori con provenienza, cambia solo qui, nello stile, porta nello stile, torna al valore ereditato; percorso degli oggetti; proprietà dinamiche aggiornate mentre si scrive. Scegliendo un oggetto nel percorso l'altezza delle pagine non cambia. | I1b, I2; motore |
| T4 | Barra: famiglia, faccia, corpo; pannello delle funzioni del font, assi, font a più assi o statico, spaziatura per corpo, margini ottici. | G3b; motore; a schermo |
| T5 | Lingua del documento e del testo selezionato, sillabazione. | motore; a schermo |
| T8 | Font variabili con l'asse della dimensione ottica (Adobe Kis VF): scegliendo la famiglia si ha il tondo da testo; il corpo non cambia faccia, la dimensione ottica la regola l'asse (automatica nella composizione); nero e corsivo danno le istanze del testo, non Caption o Display; la dimensione ottica si blocca sul corpo e torna automatica; le aggiunte portate nello stile lasciano il testo pulito. Le istanze con un nome di corpo ottico non compaiono fra le facce. | VariableFontEditorTests; motore |
| T6 | Monitor degli stili: un clic su un'aggiunta la toglie (dal tratto attorno al cursore, dalla selezione, dal paragrafo; «+N» tutte); il menu di un'aggiunta la mette nello stile, solo lei (la famiglia senza il corsivo, anche con una faccia nera personalizzata). | M1, M2, M2b, M2c |
| T7 | Tenuta delle righe nell'ispettore e nella scheda Stili: tieni col seguente, indivisibile, righe in fondo e in cima, ciascuna con la sua provenienza. | motore |
| R1 | Regole: una regola segue il testo mentre si scrive senza toccarlo; cambiare le regole si annulla; la prima riga in maiuscoletto resta esattamente sulla prima riga; una regola con condizione segue il paragrafo (una riga centrata, più righe no). | R1, R2, R3 |
| R2 | Dall'ispettore: «Crea uno stile da qui…» e «Crea una regola da qui…»; ciò che la regola dà si dice «dalla regola», e cambiato lì vale solo lì. Vista › Segni della provenienza, per finestra, solo nell'interfaccia dettagliata. | R1, R2, R3 |
| D1 | Le schede del pannello passano le modifiche al documento dopo una pausa, in un passo; Annulla ricarica la scheda; Ripristina versione salvata butta via ciò che è in attesa. | D1, R1 |

## Barra, Ribbon, righello, finestra

| # | Comportamento | Prova |
|---|---|---|
| G1 | Interfaccia essenziale e dettagliata: ispettore e percorso solo nella dettagliata; la scelta vale per le finestre nuove. | G1 |
| G2 | Barra: Annulla e Ripeti si accendono e funzionano; Nota inserisce una nota; ¶ mostra i nascosti. La barra si personalizza per livello, a gruppi che si spostano interi; un pulsante che apre qualcosa non resta acceso. | G2, G6, G6b, G7 |
| G3 | Ribbon: grassetto (conserva gli altri assi), corsivo, maiuscoletto, sottolineato e barrato, apice e pedice, colore, allineamento, interlinea, carattere speciale; valgono anche per il testo che si scrive. Lo spazio fra due controlli resta uguale cambiando la larghezza della finestra. | G3, G3b, G4, C4, C5, C6 |
| B1 | Barra di stato: i conteggi completi del documento e della selezione; il menu dello stile porta le aggiunte nello stile. | B1 |
| P1 | Righello: rientro sinistro (si porta dietro la prima riga), prima riga, destro, in un passo; in una Lista con un nome si sposta tutta la Lista (con ⌥ solo la voce); in un elenco semplice cambia il blocco di voci consecutive. Trascinando il testo si ricompone dal vivo e il documento cambia solo al rilascio. | P1–P5 |
| Z1 | Ingrandendo, se la pagina non entra più, la finestra si allarga fino ai bordi dello schermo (dentro lo spazio di «Riempi lo schermo»), poi si scorre; riducendo torna verso la misura che aveva; «Adatta alla finestra» la rimette com'era; un ridimensionamento a mano fa dimenticare la misura di prima. Dopo un pizzico la percentuale dello zoom è quella vera. | Z1, G5 |
| GR1 | Graphite: Ispettore › Composizione sul testo scelto, salvato nel file; su un font senza tabelle Graphite un avviso, che segue subito il cambio di font di uno stile; le funzioni Graphite dal pannello delle funzioni. | G4, G5, G6 |

## Sezioni e mappa

| # | Comportamento | Prova |
|---|---|---|
| SZ1 | Un file con le sezioni si apre e, salvato senza modifiche, resta identico. | motore |
| SZ2 | Scrivere nel titolo lo cambia; Invio in mezzo o in fondo al titolo fa un paragrafo del corpo della stessa sezione; all'inizio il paragrafo nuovo va prima e il titolo resta titolo. | SZ6; motore |
| SZ3 | Incollare sezioni: diventano interne della sezione in cui si incolla e portano solo il loro contenuto; il capoverso che seguiva il punto d'incollo resta alla sua sezione. Un passo di Annulla. | StoreEditingTests; motore |
| SZ4 | Inserisci › Sezione allo stesso livello, dentro questa, più fuori: un titolo vuoto al cursore (il paragrafo si spezza se serve), cursore nel titolo, un passo di Annulla; il testo che segue entra nella sezione nuova. Ruolo e stile del titolo dalle sezioni attorno. | SZ4, SZ5 |
| SZ5 | Cancella all'inizio di un titolo (o Cancella verso destra alla fine del paragrafo prima) chiede «Togliere la sezione …?»; togliendo, il titolo si unisce al paragrafo prima e le interne salgono di un livello. Una selezione che comprende l'inizio di un titolo lo toglie senza chiedere (limite noto). Inserisci › Togli la sezione toglie la più interna, senza chiedere. | SZ7, SZ8 |
| SZ6 | Percorso e ispettore della Sezione: un pulsante per livello; titolo, ruolo, livello con «Più fuori» e «Più dentro», contenuto, pagine, «Togli la sezione»; ogni cambio un passo di Annulla. | SZ9 |
| SZ7 | Dare a un paragrafo uno stile di titolo apre una sezione al livello che lo stile dichiara; dare uno stile senza livello toglie la sezione e le interne salgono. Uno stile che dichiara un altro livello sposta la sezione a quel livello con tutto il contenuto. Scheda Stili › «Apre una sezione» e «Livello». | SZ10; StoreEditingTests; motore |
| SZ8 | Il ritorno: Inserisci › «Torna a «…»» (o «Torna fuori dalle sezioni») fa tornare il capoverso del cursore e i seguenti alla sezione esterna, sulla stessa pagina; «Entra in «…»» lo toglie. | StoreEditingTests; motore |
| SZ9 | Mappa degli oggetti: le sezioni fanno da rami (con il numero se una Lista le numera), sotto paragrafi, voci, note, figure, tabelle. Un clic porta il cursore e l'ispettore. Trascinando: un capoverso fra il testo (prima delle sezioni interne), una sezione fra le sezioni con tutto il ramo, anche cambiando livello; il resto si rifiuta; nella mappa filtrata non si trascina. Un passo di Annulla. | T1, T1b, T1c, T1d |
| SZ10 | Ispettore › Sezione › Comincia: di seguito, su una pagina nuova, sulla prossima dispari; le sezioni aperte dopo, dello stesso ruolo, copiano la scelta. | SZ11 |
| SZ11 | Distanza d'apertura (stile e ispettore del paragrafo): il paragrafo che apre una sequenza scende di quella distanza dal margine superiore; un titolo di seguito no. | SZ12 |
| SZ12 | Scheda Liste: «Riparte a ogni sezione di ruolo…» e «Numera le sezioni di ruolo…»; le altre Liste ripartono a ogni passo e ne scrivono il numero («1.1»). | SZ13 |
| SZ13 | Tipi di pagina (scheda Pagine): con un nome, aggiungi, duplica, togli, rinomina (le sezioni seguono). Ispettore › Sezione: pagine, pagine pari, prima pagina; Ispettore › Pagina cambia il tipo della pagina del cursore; File › Formato della pagina cambia il predefinito. Ogni pagina col suo formato, a schermo e nel PDF; il righello segue la pagina del cursore. | SZ14, SZ15 |
| SZ14 | Inserisci › Campo: numero di pagina, numero delle pagine, titolo e numero della sezione in corso. Nel testo un carattere, nella pagina il suo valore; dopo si scrive testo; anche in una nota. Un passo di Annulla. | SZ16 |
| SZ15 | Intestazioni e piè di pagina: Inserisci › Intestazione / Piè di pagina › per tutte le pagine, dispari, pari, la prima della sezione; il flottante si àncora al titolo della sezione del cursore (o al primo paragrafo), lo stile nasce se manca, il piè di pagina con il numero di pagina. Valgono da dove sono ancorati finché un altro dello stesso tipo non li sostituisce. Numeri di pagina che proseguono o ripartono con una Lista. Limite: con il cursore nel testo dell'intestazione, il cursore si mostra sull'ultima pagina che la porta. | SZ17, SZ18; motore |

## Tabelle

| # | Comportamento | Prova |
|---|---|---|
| TB1 | Inserisci › Tabella (anche dalla barra): una tabella 3 × 3 con una riga d'intestazione dopo il paragrafo del cursore, cursore nella prima cella; spento in una tabella e in una nota. Un passo di Annulla. | TB1; motore |
| TB2 | Nelle celle: Tab e Maiuscole+Tab passano alla cella dopo e prima e ne selezionano il testo; Tab nell'ultima cella aggiunge una riga; Opzione+Tab scrive un Tab; Invio fa un paragrafo nella stessa cella. Cancellare non unisce celle né una cella al testo accanto; una selezione che attraversa celle le svuota; una tabella presa intera si cancella tutta; lo stesso per Taglia, Elimina, Cerca e sostituisci. Limiti: le frecce su e giù seguono l'ordine del testo, cella dopo cella; Indietro all'inizio di un paragrafo vuoto subito dopo la tabella non lo toglie. | TB2; motore |
| TB3 | Una tabella incollata fuori da una tabella è una tabella nuova; incollata in una cella diventa testo di quella cella. | TB3; motore |
| TB4 | Menu Tabella e ispettore Tabella: righe e colonne in più o in meno (l'ultima toglie la tabella), togli la tabella; righe d'intestazione; misure, cella del cursore, pagine occupate; «Tabella» nel percorso e nella mappa. Un passo di Annulla per comando. | TB4; motore |
| TB5 | Aspetto: scheda Tabelle (stili di tabella, rinomine seguite, tolto lo stile si torna a «Griglia»); ispettore Tabella e Cella per filetti, lati, spessore, margini interni, allineamento, fondo, ciascuno riportabile allo stile. | TB5; motore |
| TB6 | Tabella flottante con didascalia: la prima volta nascono lo stile «Tabella» e la Lista «Tabelle»; spenta, la tabella torna nel testo. | TB6; motore |
| TB7 | Unisci le celle (la selezione si allarga alle celle unite che tocca; il testo va nella cella in alto a sinistra) e Dividi la cella; le posizioni coperte si saltano con Tab. | TB7; motore |
| TB8 | Allineamento sulla virgola: il segno decimale della lingua del testo al centro della riga; in una colonna i segni stanno uno sotto l'altro; un intero si allinea sulla sua fine. | TB8; motore |

## Appunti

| # | Comportamento | Prova |
|---|---|---|
| C1 | Copia e incolla nel documento conservano note, font e funzioni; Taglia toglie e si annulla. | C1 |
| C2 | Copiando, per le altre applicazioni si mettono anche testo formattato (RTF) e testo semplice, con le note in coda. | a schermo |
| C3 | Incollare da un'altra applicazione: testo formattato RTF e RTFD con i suoi font, oppure testo semplice con gli attributi di scrittura. | C3 (testo semplice) |
| C8 | Un pezzo di un solo paragrafo incollato entra nel paragrafo, con il suo elenco. | motore (in parte) |
| C7 | Incollando da un altro documento arrivano gli stili, le Liste e le serie di note che il testo usa e che mancano. Per un nome con un'altra definizione si sceglie: vince il documento in cui si incolla, o entra una copia «Nome (2)». Un passo di Annulla. | C7; motore |

## Metodi di input e ortografia

| # | Comportamento | Prova |
|---|---|---|
| M1 | Lettere composte (´ poi e → é): il testo provvisorio del metodo di input entra come un tasto e quello definitivo lo sostituisce; spostare il cursore lo rende definitivo. | M1 |
| MI2 | Metodi di scrittura con candidati (cinese, giapponese): il riquadro accanto al testo. | non provato |
| M3 | Controllo ortografico durante la scrittura, nella lingua di ogni parola; menu del clic destro con suggerimenti, Ignora, Impara. | a schermo |

Non provati neppure: Modifica › Strumenti di scrittura di macOS e la dettatura.

## File e ricerca

| # | Comportamento | Prova |
|---|---|---|
| F1 | Salva, Apri, Ripristina versione salvata; si aprono i `.grx` e i vecchi `.wpx`. | motore |
| F2 | Esporta come PDF. | motore |
| F3 | Font mancanti: avviso all'apertura, testo con un font di ripiego, nome originale conservato nel file. | motore; a schermo |
| F4 | Formato della pagina (ispettore della Pagina e File › Formato della pagina…, ⇧⌘P): formato, orientamento, misure, margini, pagine affacciate. Ogni campo accetta mm, cm, pollici, pt, pica e «1p6», con la virgola o il punto, e i conti (+ − × ÷, parentesi, unità diverse); una scrittura non valida torna al valore di prima, misure impossibili fanno un bip. Un passo di Annulla. | F4 |
| F5 | Cerca e sostituisci: conto, frecce che ricominciano, Sostituisci, Sostituisci tutto in un passo, opzioni, modello non valido. | F1 |

## Misure di velocità

A richiesta: `WP_MISURE=1 swift test --filter Measurements` (il nome della suite è «Misure», ma il filtro va sul nome
del tipo; con `-c release -Xswiftc -enable-testing` i tempi sono quelli dell'app). Documenti di prova di circa 100 pagine; le misure stampano tempi della
composizione, di un tasto e di un cambio di stile.
