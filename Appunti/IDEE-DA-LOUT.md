# Idee da Lout

Scritto il 9 novembre 2026, dopo una lettura di Lout 3 (versione del 19 giugno 2023, in `~/Downloads/lout-2023_06_19`): il manuale di progetto di Jeffrey Kingston (`doc/design`), la guida per esperti (`doc/expert`) e i sorgenti.

Lout è un compositore a oggetti e funzioni, molto vicino all'idea di GRIFFR. Si prendono le idee, non il codice: è in C, scrive PostScript, ed è sotto GPL. I suoi font, la sillabazione e la composizione delle righe sono più semplici di quelli di GRIFFR, e la sua sintassi non serve.

Le idee sono in ordine di utilità rispetto alle tappe di [RIASSUNTO-RESIDUO.md](RIASSUNTO-RESIDUO.md).

## 1. Galley: un oggetto e il posto dove deve comparire

Tappe 4 e 5 (flottanti derivati, migrazione di tabelle e flottanti).

In Lout un *galley* è un oggetto più l'indicazione del posto in cui deve comparire. Il posto è un simbolo ricevente: il testo della pagina, il piede, il margine, la fine del capitolo. La destinazione si dice con:

- `preceding`: il posto più vicino prima;
- `following`: il più vicino dopo;
- per i galley che continuano: il primo posto successivo che ha spazio per il pezzo seguente.

Note a piè di pagina, flottanti, note marginali, sommario e indice funzionano tutti così. Un galley che non entra in un posto si divide fra i suoi *componenti* (le parti fra due punti di divisione ammessi) e prosegue nel posto successivo. Un posto che non riceve niente sparisce.

Per GRIFFR sarebbe il gemello dichiarativo di «Scrivi risultato → Qui»:

- un campo prende un valore da un altro punto e lo scrive qui;
- un galley prende un oggetto da qui e lo manda là.

La nota marginale della quinta parola diventa: «oggetto ancorato alla quinta parola, mandato nel posto Margine più vicino che segue, a 1 cm dal bordo». Con la stessa grammatica si possono descrivere note, figure e tabelle, invece di un percorso per ogni caso.

Fonti: `doc/expert/pri_gall` (introduzione), `doc/expert/det_gall` (regole dei posti e dei componenti), `doc/design/s5_4` (algoritmo che svuota i galley nei posti).

## 2. Rimandi con etichetta e direzioni relative

I «rimandi a un paragrafo» e la «pagina d'inizio di una sezione» rimasti da fare nei campi.

Ogni oggetto può avere un'etichetta (`@Tag`) data dall'autore, e un rimando lo raggiunge per nome (`@Table&&cities`). Si può anche chiedere `&&preceding`, `&&following` o `&&foll_or_prec`: per esempio «il titolo di capitolo precedente». Così le testatine correnti non sono un meccanismo a parte. `@Tagged` aggiunge altre etichette allo stesso oggetto.

Per GRIFFR:

- serve un'identità che si salva nel file. L'esperimento con Alloy ha trovato che `ParagraphID` non si salva ([Alloy/RISULTATI.md](Alloy/RISULTATI.md)); un'etichetta scelta dall'autore e salvata è la risposta di Lout;
- nelle catene di `FieldFormula` sarebbero due passi nuovi: «Oggetto con etichetta…» e «Precedente / Seguente di ruolo…».

Fonti: `doc/expert/pri_cros`, `doc/expert/pre_tagg`, `doc/design/s3_3` e i capitoli sui rimandi.

## 3. Indice e bibliografia come galley ordinati da fondere

L'«indice generato» del lavoro tipografico indipendente.

Ogni voce d'indice è un piccolo galley con una chiave di ordinamento, mandato al posto «Indice». Se due voci hanno la stessa chiave:

- nella bibliografia si tiene la prima e si scartano le altre (una fonte citata due volte compare una volta);
- nell'indice si fondono con `@Merge`: «Pisa, 12» e «Pisa, 40» diventano «Pisa, 12, 40».

La fusione usa tre operazioni sui paragrafi: `@Common` (la parte iniziale uguale: «Pisa,»), `@Rump` (il resto del secondo: «40») e `@Meld` (il paragrafo più corto che contiene i due come sottosequenze: «Pisa, 1, 2» e «Pisa, 2, 3» danno «Pisa, 1, 2, 3»).

Fonti: `doc/expert/det_sort`, `doc/expert/pre_rump`, e `doc/expert/exa_inde` per l'esempio completo.

## 4. Impaginazione ottimale della pagina intera

L'«ottimizzazione considerando la pagina intera».

È l'equivalente per le pagine del compositore ottimale dei paragrafi. Nella prima composizione Lout registra le altezze dei componenti, gli spazi fra loro e lo spazio di ogni posto. Alla fine calcola le divisioni migliori e le scrive in un archivio; nella seconda composizione le usa. Riduce molto i bianchi in fondo alle pagine prima di una figura grande.

Il manuale avverte che a volte non converge, quasi sempre con figure e note ancorate vicino al bordo della pagina. Serve quindi un limite di iterazioni e una diagnosi. GRIFFR fa già una seconda composizione per il numero delle pagine: la struttura c'è.

Fonte: `doc/expert/det_opti`.

## 5. Pagine e posti come oggetti

In Lout la pagina non è un'impostazione: è un oggetto con dentro dei posti riceventi (`@TextPlace`, `@FootSect`). La sequenza delle pagine è un oggetto che si ripete con il numero che cresce (`@PageList`), e la zona delle note è una lista di posti per le note.

Per GRIFFR: colonne, pagine miste e zone delle note marginali diventerebbero definizioni di pagina con più posti, nello stesso linguaggio a oggetti degli stili. Va insieme all'idea 1.

Fonte: `doc/design/s3_2`.

## Idee minori

- **Vincoli di dimensione con un punto di allineamento.** Lo spazio disponibile si esprime come tre limiti: a sinistra del punto, a destra, e in tutto. Utile per allineare sulla virgola decimale o su un segno, e per il numero accanto al titolo. Fonte: `doc/design/s5_3`.
- **Galley orizzontali.** Kingston li ha progettati ma non realizzati: le righe di un paragrafo come posti riempiti dal testo. Darebbero paragrafi sagomati e testo attorno alle figure. Fonte: `doc/design/s5_5`.
- **Pacchetti di definizioni** (`@Use`, `export`): GRIFFR li ha già con l'importazione delle definizioni.

## Seconda lettura: la guida per esperti · 9 novembre

Dalla guida per esperti (`doc/expert/outfile.pdf`, 120 pagine; sorgenti in `doc/expert`), confrontata con il codice di GRIFFR.

### 6. Collegamenti nel PDF · realizzato il 9 novembre

Fatto in `PDFNavigation.swift`: segnalibri, collegamenti richiamo ↔ nota, etichette delle pagine. Il resoconto è in [RIASSUNTO-RESIDUO.md](RIASSUNTO-RESIDUO.md). Restano i collegamenti dei campi e dei rimandi, che aspettano l'idea 2.

Lout ha `@LinkSource` e `@LinkDest` (un punto che si clicca e un punto d'arrivo, legati dalla stessa etichetta dei rimandi), `@URLLink` per gli indirizzi web e `@PageLabel` per dare un nome alle pagine. Avvisa se una sorgente non ha destinazione o se due destinazioni hanno lo stesso nome.

GRIFFR oggi non scrive collegamenti nel PDF: `PDFRenderer.swift` scrive i tag della struttura, ma non collegamenti, segnalibri (outline) o etichette delle pagine. È un lavoro piccolo rispetto agli altri, e utile subito:

- richiamo di nota → nota, e ritorno;
- campi e rimandi (idea 2) → l'oggetto a cui puntano;
- voci di sommario e d'indice → la pagina;
- segnalibri del PDF dai livelli dei titoli (`outlineLevel`);
- etichette delle pagine (i, ii, iii per le pagine iniziali), così il lettore PDF mostra lo stesso numero della pagina stampata.

Core Graphics ha `CGPDFContextSetURLForRect`, `CGPDFContextAddDestinationAtPoint` e `CGPDFContextSetDestinationForRect`; segnalibri ed etichette si aggiungono dopo, con PDFKit o modificando il catalogo del PDF. Da verificare.

Fonti: `doc/expert/pre_link`, `doc/expert/pre_page`.

### 7. Unità relative al carattere e alla riga

Oltre alle unità fisse, Lout ha `f` (la dimensione del font), `s` (lo spazio fra parole) e `v` (la distanza fra le righe). In più distingue due modi di misurare uno spazio verticale:

- **da segno a segno** (`x`): da linea di base a linea di base, per i paragrafi;
- **da bordo a bordo** (`e`): per figure e tabelle, la cui linea di base non c'entra.

Il capitolo sui paragrafi (`exa_para`) spiega perché: uno spazio fra paragrafi scritto in centimetri non cresce quando il documento passa all'interlinea doppia; scritto in `v` sì. E i «numeri magici» vanno nelle definizioni con un nome, non sparsi negli stili.

GRIFFR oggi ha solo unità fisse (`LengthUnit`: mm, cm, in, pt, pc). Unità come «righe» ed «em», anche solo dentro le formule degli stili, aiuterebbero la griglia delle linee di base (nella lista del lavoro tipografico): uno spazio di «1 riga» resta sulla griglia anche se cambia l'interlinea. Le formule riutilizzabili coprono già la seconda parte della lezione.

Fonti: `doc/expert/pre_conc` (unità e modi), `doc/expert/exa_para`.

### 8. Intestazioni che si ripetono quando un oggetto continua

GRIFFR ripete già le righe d'intestazione delle tabelle sulla pagina dopo. In Lout è un caso di una regola generale: ogni galley può segnare dei componenti come intestazioni (`@BeginHeaderComponent`, `@EndHeaderComponent`), che si ripetono in testa a ogni posto in cui il galley continua. Va con l'idea 1: la stessa regola darebbe le righe d'intestazione delle tabelle, «(continua)» su una nota o un riquadro diviso, la riga dei titoli di un glossario.

Fonte: `doc/expert/pre_head`.

### 9. Lo stile viene dal posto

In Lout un galley prende lo stile del primo posto in cui si colloca: le note dentro un capitolo a due colonne vanno al piede della colonna e ne prendono la misura e il font. In GRIFFR la collocazione è oggi un elenco chiuso di sei posti (`FloatStyle.Placement`: piede di pagina, fine del documento, margine esterno, figura, testata e piede delle pagine). Se diventano posti veri (idee 1 e 5), una nota potrebbe prendere la misura e lo stile dalla zona in cui cade: nel margine stretta e piccola, al piede larga.

Fonti: `doc/expert/det_size` (inizio), `doc/expert/exa_chap`.

### 10. Testo e figure alternati nella colonna

Per le figure Lout descrive la colonna come «testo, posto per figura, testo, posto per figura…». Un simbolo (`@NotRevealed`) impedisce che, senza figure, la colonna si divida in tanti pezzi di testo vuoti; `@OneOf` sceglie fra pagine diverse (con o senza zona delle figure) quella che contiene il posto che serve. Il manuale racconta i problemi che hanno portato a questi due simboli: è una lista utile di casi difficili per le figure di GRIFFR, che oggi si collocano «secondo le posizioni ammesse, come in LaTeX».

Fonti: `doc/expert/pre_notr`, `doc/expert/pre_oneo`, `doc/expert/exa_page`.

### Minori

- **Tabelle di valori** (`@Case` con `@Yield` ed `else`): «1 → st, 2 → nd, altrimenti th», o i nomi dei mesi. Con `@Moment` (data e ora) Lout scrive la data del documento. Per GRIFFR: un risultato «Data» nelle catene dei campi, con i nomi dei mesi nella lingua del paragrafo. Fonti: `pre_case`, `pre_mome`.
- **Lingue**: ogni lingua dichiara anche i segni che chiudono una frase; Lout li usa per lo spazio dopo il punto. Un piccolo esempio di «regole tipografiche per lingua». Fonte: `pre_lang`.
- **Celle che si estendono** su più righe e colonne senza dover allineare i loro segni (`@StartHVSpan`). Fonte: `pre_span`.

## Che cosa non serve

La sintassi del linguaggio, l'uscita PostScript, la gestione dei font e la sillabazione.
