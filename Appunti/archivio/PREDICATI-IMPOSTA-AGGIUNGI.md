# Prima tappa · Contratti di Imposta e Aggiungi

4 novembre 2026 · Implementazione del nucleo di valutazione nel fork

Un'operazione ha tre parti distinte, predicato, proprietà e argomento. Riceve lo stato risolto dell'oggetto e restituisce un nuovo stato oppure una diagnosi. La proprietà stabilisce quali predicati e quali tipi di argomento sono ammessi.

Il primo nucleo eseguibile è in [StylePredicates.swift](../Sources/Typesetting/StylePredicates.swift). La struttura salvata delle formule e il collegamento di tutti gli stili alla bacheca seguono nelle tappe successive del [piano](PIANO-STILI-FORMULE.md).

## Font

L'argomento Font indica qui il ruolo tipografico completo, tondo, corsivo, grassetto oppure grassetto corsivo. Famiglia, faccia precisa e corpo restano proprietà distinguibili.

| Prima | Imposta grassetto | Aggiungi grassetto | Imposta corsivo | Aggiungi corsivo |
|---|---|---|---|---|
| Tondo | Grassetto | Grassetto | Corsivo | Corsivo |
| Corsivo | Grassetto | Grassetto corsivo | Corsivo | Corsivo |
| Grassetto | Grassetto | Grassetto | Corsivo | Grassetto corsivo |
| Grassetto corsivo | Grassetto | Grassetto corsivo | Corsivo | Grassetto corsivo |

Imposta sceglie il ruolo completo nella famiglia corrente. Aggiungi unisce i tratti richiesti a quelli in ingresso. Aggiungere il tondo è l'operazione neutra. Aggiungere un tratto già presente conserva il risultato.

La realizzazione del ruolo passa dal FontRoleResolver dell'app e dalle equivalenze del documento. Una faccia variabile conserva gli assi compatibili estranei al ruolo. Una faccia libera cui si aggiunge il solo corsivo segue la politica esistente di conservazione del peso. Se il ruolo corrente non è riconoscibile o manca una realizzazione di quello richiesto, la valutazione restituisce una diagnosi.

Corpo, colore, lingua e proprietà del paragrafo restano fuori dalla modifica del ruolo. Le funzioni del font seguono le regole del risolutore quando si cambia faccia.

## Lunghezze

Il nucleo converte i valori nelle unità già supportate da GRIFFR, mm, cm, in, pt e pc. Un argomento di lunghezza resta distinto da un intero senza unità o da un ruolo del font.

| Proprietà | Imposta | Aggiungi | Validità del risultato |
|---|---|---|---|
| Corpo | Sostituisce la misura | Somma la variazione | Finito e maggiore di zero |
| Spazio prima e dopo | Sostituisce la misura | Somma la variazione | Finito e non negativo |
| Spazio fra righe | Sostituisce la misura | Somma la variazione | Finito e non negativo |
| Rientro sinistro, destro e di prima riga | Sostituisce la misura | Somma la variazione | Finito, anche negativo |

Una variazione può essere negativa se il risultato rispetta il contratto. Per esempio 12 pt più −6 pt produce 6 pt. Un valore non finito o un overflow nella conversione viene rifiutato.

## Proprietà discrete

Allineamento e lingua ammettono inizialmente Imposta, con un valore del proprio tipo. Per lingua il valore assente ripristina la lingua di documento. Il menu dei predicati deve derivare dalle operazioni ammesse dalla proprietà.

Le altre proprietà ordinarie avranno inizialmente Imposta con gli argomenti già rappresentati dal programma. Questo comprende famiglia, faccia precisa, colore, maiuscoletto, funzioni del font, assi, decorazioni e scelte di composizione. Aggiungi per funzioni e decorazioni richiede un contratto per la combinazione e i conflitti. Gli effetti di lista, sezione, tenuta e collocazione appartengono alle rispettive firme delle tappe successive.

Le precedenze rispetto ai valori manuali e l'eventuale forza obbligatoria della regola sono indipendenti da Imposta o Aggiungi.

## Ordine e rivalutazione

Le operazioni di una catena leggono ciascuna l'uscita della precedente, nell'ordine dichiarato. Imposta spazio prima a 6 pt seguito da Aggiungi 6 pt produce 12 pt. Invertire le due operazioni produce 6 pt.

La funzione di valutazione richiede un ingresso esplicito. Per ogni ricomposizione il chiamante riparte dall'ingresso della formula, ricavato dal contesto e dall'eredità correnti. Il risultato precedente non viene accumulato automaticamente. Cento valutazioni di Aggiungi 6 pt sullo stesso ingresso di 12 pt producono sempre 18 pt.

La valutazione usa stati per valore. Se una delle operazioni fallisce, l'ingresso del chiamante resta intatto. L'eredità degli stili e l'ordine tra contributi richiedono ancora il collegamento della tappa 2.

## Verifiche eseguite

Le prove esercitano tutte le combinazioni fra quattro ruoli in ingresso e quattro richieste per entrambi i predicati, le equivalenze personalizzate, gli assi variabili, le conversioni fra unità, i risultati negativi ammessi, l'ordine della catena e cento rivalutazioni. Comprendono inoltre incompatibilità degli argomenti, predicati non ammessi, valori non finiti, overflow e ruolo indisponibile.

[Prove dei predicati](../Tests/TypesettingTests/StylePredicatesTests.swift) · [Risolutore dei ruoli già esistente](../Sources/Typesetting/FontRoleResolver.swift)

La corsa finale del 4 novembre riporta 10 prove nei tre contenitori selezionati, tutte superate, comprese cinque nuove prove dei predicati e quelle esistenti del risolutore. È verificata anche la faccia effettiva del caso iniziale, HoeflerText-Black per Imposta e HoeflerText-BlackItalic per Aggiungi. La compilazione debug è riuscita.

Questa tappa consegna i contratti e il nucleo di valutazione. La tappa 2 collegherà tali operazioni alla rappresentazione delle definizioni di stile, prima di esporle come pills nella bacheca.
