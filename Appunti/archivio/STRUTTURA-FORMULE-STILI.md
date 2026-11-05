# Seconda tappa · Formule associate agli stili

4 novembre 2026

NamedStyle ora conserva un elenco ordinato di StyleFormula. Ogni formula ha un'identità stabile nel proprio stile e un'operazione composta da predicato, proprietà e argomento tipizzato. Il primo nodo eseguibile è Imposta o Aggiungi su un oggetto destinatario determinato dal tipo dello stile.

Per uno stile di carattere sono ammessi font e corpo. Lo stile di parola può aggiungere la lingua. Lo stile di paragrafo può operare anche su rientri, spazi e allineamento. Il lettore verifica la compatibilità prima di accettare una formula.

[Definizione delle formule](../Sources/Typesetting/StyleFormula.swift)

## Valutazione ed eredità

Il risolutore conserva i passaggi ereditati e valuta le formule nell'ordine dichiarato. Un rientro di 12 pt nello stile di base, seguito da Aggiungi 6 pt nel figlio, produce 18 pt. Cambiare il rientro della base a 24 pt produce 30 pt. Una dichiarazione successiva esplicita di 8 pt nel discendente produce 8 pt.

Durante la migrazione le proprietà storiche restano dichiarazioni compatibili. I documenti che ne usano soltanto quelle seguono la risoluzione precedente. La traduzione dei predefiniti in formule e la loro esposizione nella bacheca sono il passo successivo.

La risoluzione di carattere e quella di paragrafo valutano le parti pertinenti. La funzione di valutazione esplicita restituisce un errore in caso di operazione impossibile sul contesto concreto. Gli accessi storici che restituiscono un valore senza errori usano la resa delle dichiarazioni compatibili come ripiego. La bacheca degli stili reali dovrà presentare queste diagnosi prima di attivare definizioni problematiche.

## Controlli esistenti

La scheda Stili riconosce l'origine propria o ereditata delle proprietà dichiarate con formule. La modifica di una proprietà tramite i controlli costanti sostituisce le formule pertinenti con il valore scelto. Ripristinare l'eredità le rimuove per quella proprietà. La scelta visuale fra formula e costante sarà resa esplicita nella tappa delle interfacce.

Le formule seguono l'importazione di uno stile e la sua rinomina. Gli argomenti iniziali sono costanti tipizzate, quindi non introducono ancora riferimenti fra formule da riscrivere. Gli identificativi sono locali alla definizione di stile, così una copia indipendente può conservare la propria struttura interna.

## Salvataggio

Il formato 4 conserva id, predicato, proprietà, tipo dell'argomento, valore e unità. La versione viene richiesta solo quando sono presenti formule o quando si riapre un documento già v4. Rimane attiva la protezione del documento originale al cambio di versione.

Per i valori relativi serve conservare la base di documento. Il writer usa quell'ingresso, anziché ricavarlo dal corpo già aumentato del testo. Cinque salvataggi e riaperture di un corpo iniziale di 12 pt con Aggiungi 2 pt mantengono il risultato di 14 pt.

Il ponte verso il deposito conserva le definizioni e la base. Le formule malformate, i bersagli incompatibili e le identità duplicate nello stesso stile vengono rifiutati dal lettore.

## Campione e prove

[Documento di confronto fra Imposta e Aggiungi](prova-stili-formule.grx)

Il campione parte da un carattere corsivo. Forte come formula aggiunge il grassetto e produce nero corsivo. Nero assoluto imposta il grassetto e produce nero tondo. Citazione relativa usa una formula per aggiungere 6 mm al rientro.

Le prove mirate coprono font effettivi, XML, deposito, rientri ereditati, modifica da controllo, ripristino dell'eredità, importazione, rinomina, stabilità delle posizioni composte, corpo relativo e aggiornamento tramite editor con Annulla e Ripeti.

[Prove del motore](../Tests/TypesettingTests/StyleFormulaTests.swift) · [Prova nell'editor](../Tests/WordProcessorTests/PageStartSpacingTests.swift) · [Piano](PIANO-STILI-FORMULE.md)

## Esito delle verifiche

Il controllo mirato ha superato 49 prove, 44 del motore e 5 dell'editor. La suite completa ha superato tutte le 186 prove dell'editor. Le 466 prove del motore riportano 20 segnalazioni già presenti nella corsa di riferimento, con nessuna nuova segnalazione. Il confronto include i problemi dei font di prova mancanti nell'ambiente.

Il campione Annapurna riscritto dal nuovo modulo coincide byte per byte con quello prodotto dal motore precedente. Pagina, intervallo, origine e larghezza coincidono per tutte le 104 righe del campione. Il documento di prova v4 viene letto, composto e riscritto correttamente dal nuovo modulo.
