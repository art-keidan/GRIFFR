# Quarta tappa · Controlli e bacheca condividono la definizione

I controlli ordinari dello stile scrivono formule Imposta per le proprietà del vocabolario attuale. Cambiare il corpo da 14 a 16 pt modifica il nodo esistente, conservandone l'identità. Un valore fisso resta dichiarato anche quando coincide con quello ereditato; tornare a ereditare è un comando distinto.

## Come provarlo

1. Aprire l'app aggiornata e la scheda **Stili** dell'interfaccia avanzata.
2. Selezionare **Testo** e cambiare il corpo. Aprire la bacheca: la pill Corpo mostra la stessa definizione.
3. Modificare la pill e scegliere **Applica al documento**. Il controllo e il testo seguono la modifica; Annulla e Ripeti riportano in pari le interfacce.
4. In uno stile con **Aggiungi** o **Sottrai**, leggere la formula sotto al risultato. Il controllo del valore fisso rimane inattivo quando la sua modifica eliminerebbe il calcolo.
5. Scegliere **Bacheca** per modificare il calcolo, oppure **Usa il risultato come valore fisso** dal menu del controllo. Questa seconda scelta sostituisce la catena pertinente con Imposta.
6. Scegliere **Togli da questo stile (lo eredita)** per rimuovere la dichiarazione propria. Se il genitore contiene un calcolo, questo torna visibile con il suo proprietario.

L'ispettore del testo conserva la distinzione fra **Cambia solo qui** e **Cambia nello stile**. Il primo modifica l'aspetto locale senza riscrivere le formule. Il secondo mostra il calcolo che riceverebbe la modifica; la sostituzione con un valore fisso è esplicita. Dal collegamento Bacheca si apre lo stile che possiede la formula, anche quando è ereditata.

## Sincronizzazione e bozze

Una bacheca senza modifiche dell'autore si aggiorna quando cambia lo stile da un controllo o con Annulla. La conversione automatica delle vecchie dichiarazioni non conta come una modifica dell'autore ai fini di questa protezione.

Una bacheca con una bozza mantiene il lavoro già svolto. Se lo stesso documento cambia da un altro pannello, la bacheca segnala il conflitto e offre il ricaricamento; Applica non sovrascrive una definizione più recente.

Il campione della bacheca parte dalla base salvata del documento. Gli stili di parola e carattere ricevono il contesto del paragrafo e della parola della selezione. La scelta del ruolo nel campione rimane disponibile per gli esperimenti.

## Aggiornamento dalla selezione e altre operazioni

**Aggiorna lo stile dalla selezione** conserva le formule che già producono l'aspetto selezionato. Cambia soltanto le proprietà diverse. Se occorre sostituire un calcolo, presenta le proprietà coinvolte e richiede la scelta **Sostituisci con valori fissi**; Annulla conserva la definizione precedente.

Anche i comandi che portano un valore locale nello stile scrivono la definizione comune. I relativi menu dichiarano quando l'azione sostituisce una formula. Nuovi stili ricavati dal testo traducono le proprietà supportate in formule. Copia, rinomina e importazione conservano le formule e le loro identità locali allo stile.

I tratti del font esplicitamente disattivati diventano Sottrai nelle catene che si possono convertire mantenendo la resa. Le catene con scelte avanzate del font restano protette dal percorso di compatibilità.

## Formato e perimetro

La faccia precisa scelta nei controlli è ora rappresentabile con **Imposta · Faccia precisa · nome della faccia**. È distinta dal ruolo **Font · Grassetto/Corsivo**. Questo argomento richiede il formato **7**; le altre formule continuano a richiedere soltanto la propria versione minima. Il lettore rifiuta la nuova costruzione dichiarata in un formato precedente.

Funzioni del font, assi e altre proprietà non ancora presenti nel vocabolario rimangono nei rispettivi adattatori compatibili. L'aggiornamento dalla selezione conserva e aggiorna i dettagli avanzati separatamente. Condizioni, comportamenti, tabelle e flottanti restano nelle tappe successive del piano.

## Verifiche

Le prove seguono i percorsi controllo → formula → testo e bacheca → controllo → testo, insieme ad Annulla, Ripeti, file, eredità, valore fisso esplicito, bozze concorrenti, aggiornamento dalla selezione e base del documento diversa da 12 pt. È inclusa la regressione di Sottrai sul grassetto manuale.

La verifica visiva manuale dei pannelli resta da svolgere: questa sessione verifica compilazione e comportamenti attraverso le prove dell'editor, senza controllo diretto dell'interfaccia macOS.

[Prove dei controlli](../Tests/WordProcessorTests/FormulaControlTests.swift) · [Definizione comune](../Sources/Typesetting/StyleFormulaControls.swift) · [Piano](PIANO-STILI-FORMULE.md)

## Esito delle verifiche

La suite completa supera tutte le 198 prove dell'editor presenti in quella corsa. Le 470 prove del motore riportano le stesse 20 segnalazioni preesistenti relative ai font di prova mancanti, senza nuove segnalazioni.

Dopo l'ultimo adeguamento alle equivalenze tipografiche del documento, le 39 prove mirate sono tutte passate: 19 dell'editor e 20 del motore. Comprendono la nuova prova che confronta la faccia mostrata nel controllo con quella della bacheca usando un'equivalenza personalizzata.

Il documento Annapurna conserva XML identico. Nel confronto fra il motore originale e quello corrente, con i programmi di controllo ricompilati con gli stessi parametri, coincidono le posizioni di tutte le 104 righe.
