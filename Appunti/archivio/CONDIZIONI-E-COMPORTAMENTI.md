# Quinta tappa · Condizioni, destinatari e comportamenti

5 novembre 2026

Una formula conserva ora, oltre a identità, predicato e argomenti, una condizione e un destinatario. Il tipo resta limitato e guidato: la bacheca propone le scelte compatibili con l'operazione.

## Condizioni e destinatari

Le pill **Quando** permettono Sempre, Primo della pagina, Inizio sequenza e Dopo uno stile di paragrafo. A queste si può aggiungere una condizione numerica: parole, righe, percentuale di riempimento dell'ultima riga o righe con trattino, con confronto e soglia.

Le pill **Su** scelgono il paragrafo, la prima lettera, le prime N parole, la prima frase, le prime N righe, l'ultima riga, sigle, numeri, numeri romani o una selezione condivisa già definita. Le proprietà del paragrafo richiedono il paragrafo intero.

**Imposta · Stile dei destinatari · Forte**, per esempio, può agire sulle prime due parole oppure sulla quinta parola trovata da una selezione condivisa. Il trattamento richiamato deve essere uno stile di resa: per ora non si possono richiamare ricorsivamente altri trattamenti contestuali.

Il campione offre la posizione a inizio pagina, il paragrafo precedente e l'inizio sequenza. Per le misure geometriche si possono indicare righe, percentuale e trattini di prova; il numero di parole si ricava dal campione. La scheda indica se la condizione è soddisfatta. I destinatari interni si trattano nella composizione del documento, senza cambiare il testo sorgente.

## Momenti di esecuzione

La bacheca distingue le fasi e consente di riordinare le formule all'interno della stessa fase:

1. **Formattazione di base**: le operazioni ordinarie dello stile.
2. **Durante la collocazione**: distanza a inizio pagina, distanza di apertura e tenuta delle righe. Sono richieste al compositore.
3. **Contesto del testo**: condizioni sul predecessore o sull'inizio sequenza e trattamenti di parole o righe.
4. **Composizione naturale**: condizioni numeriche e condizioni sulla pagina. Le misure si leggono prima di applicare gli effetti di questa fase, secondo la politica del motore esistente.
5. **Quando assegni lo stile**: apertura di una sezione e livello del titolo.
6. **Quando premi Invio**: scelta dello stile del nuovo paragrafo.

Le fasi di collocazione e di azione sono distinte dalle formule di resa. All'interno di ciascuna fase gli effetti contestuali nuovi si compongono sul valore corrente, nell'ordine dichiarato. Le condizioni non costituiscono un ciclo che ricomincia finché il proprio effetto le rende false.

La distanza a inizio pagina usa il meccanismo di collocazione già verificato: continua a seguire il titolo anche quando la tenuta lo sposta su un'altra pagina. Le formule non creano sezioni durante il calcolo di una pagina.

## Comportamenti disponibili

- **Distanza a inizio pagina**: definita come formula, con condizione Primo della pagina; sono possibili distanza, zero esplicito e disattivazione.
- **Distanza di apertura**: per l'apertura di una sequenza.
- **Tieni con il prossimo**, **Paragrafo indivisibile**, **Righe in fondo**, **Righe in cima**: dichiarazioni convertibili in formule.
- **Apre sezione** e **Livello del titolo**: mantengono il comportamento di assegnazione già esistente.
- **Stile dopo Invio**: sceglie uno stile di paragrafo esistente. Stesso stile disabilita un'eventuale scelta ereditata. Nuova riga e cambio di stile appartengono a un passo di annullamento.

Le richieste che influenzano collocazione, struttura o creazione del paragrafo hanno condizioni compatibili con la propria fase. Non tutte le combinazioni geometriche arbitrarie sono offerte.

## Regole già esistenti

La bacheca comprende la sezione **Regole**, con gli stessi controlli di condizione e destinatario. È possibile cambiare ambito, condizione, ricerca, trattamento e stato attivo.

Le regole storiche restano nel documento come dichiarazioni compatibili: ne vengono conservati ordine, fase e precedenza rispetto alla formattazione locale. Le formule contestuali nuove appartengono agli stili e sono compilate in richieste di resa solo durante la composizione. I trattamenti nuovi agiscono sul valore corrente; le eccezioni esplicite alle regole continuano a essere rispettate.

Questa distinzione evita una migrazione silenziosa che cambierebbe l'aspetto dei documenti precedenti. Gli stili temporanei usati dalla composizione non entrano nel file né nell'elenco degli stili dell'autore.

## File e riferimenti

Condizioni, destinatari e nuove richieste richiedono il **formato 8**. Il file conserva identità, unità, soglie, confronti e riferimenti a stili e selezioni. Versioni precedenti che dichiarano questi costrutti vengono rifiutate. Rimane attiva la protezione del documento originale quando cambia il formato.

Rinominare uno stile aggiorna anche i riferimenti delle formule. L'importazione porta gli stili dipendenti e le selezioni condivise, risolvendo i conflitti. Un riferimento mancante viene segnalato prima di applicare la bozza.

## Prova pratica

Aprire [il documento di esempio](prova-condizioni-comportamenti.grx) nell'app aggiornata, poi **Formato → Compositore di stili…**.

- In **Titolo capitolo** si trovano distanza a inizio pagina, tenuta, apertura di capitolo e stile dopo Invio. Al termine del titolo, Invio prepara un capoverso Testo.
- In **Testo** il rientro della prima riga viene tolto quando il paragrafo segue Titolo capitolo.
- In **Citazione breve** una condizione sul numero di parole decide la centratura.
- In **Paragrafo marcato** una selezione condivisa individua la quinta parola e le applica Evidenza.

Le prove includono resa rispetto al predecessore, condizioni numeriche sulla composizione naturale, stabilità della collocazione, Invio e sezioni, selezioni condivise, importazione, annullamento e salvataggio. La verifica visiva manuale della finestra resta da svolgere: la sessione verifica compilazione e comportamenti attraverso le prove dell'editor.

[Piano](PIANO-STILI-FORMULE.md) · [Condizioni](../Sources/Typesetting/StyleConditions.swift) · [Composizione delle formule](../Sources/Typesetting/StyleRuleCompilation.swift)

## Esito delle verifiche

La verifica completa ha superato tutte le 202 prove dell'editor presenti in quella corsa. Le 475 prove del motore riportano le stesse 20 segnalazioni preesistenti sui font di prova mancanti, senza nuove segnalazioni.

Le ultime 48 prove mirate sono tutte passate: 22 dell'editor e 26 del motore. Comprendono composizione di più effetti contestuali, provenienza nell'ispettore, eccezioni locali, equivalenze dei font e identità locali delle formule nell'eredità.

Il documento di esempio si apre, si compone e si riscrive; una seconda riapertura conserva XML e posizioni identici. Il riferimento Annapurna mantiene XML e tutte le 104 righe nelle stesse posizioni del motore originale ricompilato con gli stessi parametri di controllo. Il pacchetto finale dell'app è stato compilato e verificato.
