# Oggetti editoriali, sequenze e presentazioni · analisi

7 novembre 2026. Analisi da discutere prima di implementare; nessun codice è stato cambiato. Risponde alla proposta su contatori, liste, campi, note e flottanti, ed è confrontata con i sorgenti di oggi.

## Il giudizio in breve

Le due intuizioni sono **la stessa idea vista da due lati**, e sono buone. La prima dice che un numero è la posizione di un oggetto in una sequenza. La seconda dice che un oggetto può mostrarsi in più punti. Insieme danno un principio solo:

> **Lo stile dice come; l'occorrenza dice chi è e che cosa ha scritto l'autore; numeri, pagine e collocazioni si calcolano.**

GRIFFR ne contiene già metà, più di quanto la proposta supponga:

- **Le Liste sono già contatori con un nome.** `ListDefinition` ([Lists.swift](../Sources/Typesetting/Lists.swift)) si descrive come «la definizione di una numerazione, a cui rimandano voci di elenco, esempi e note», ha inizio, fine, serie di simboli, ripartenza per lista superiore, pagina o sezione (`ListParent`), prosecuzione dopo il testo normale (`continues`), numeri gerarchici («1.2», `showsParent`), numerazione dei capitoli (`numbersSections`). Il numero **non si salva**: «si calcola componendo la pagina, come per le note» (`ListItem`).
- **Note, figure e testatine sono già un oggetto solo.** `FloatingObject` ([Document.swift](../Sources/Typesetting/Document.swift)) è un contenuto scritto dall'autore, ancorato a un carattere del testo, con uno **stile di flottante** (`FloatStyle`) che sceglie la collocazione (piede, fine del documento, margine esterno, figura, intestazione, piè di pagina), la Lista che lo numera, il richiamo e lo stile del contenuto.
- **Campi e «Scrivi risultato» sono già presentazioni calcolate.** `FieldFormula` legge un risultato e lo scrive nel punto del campo; le testate (`HeadingComposition`) e `WrittenResult` scrivono numeri e testi accanto o dentro i paragrafi.

Manca l'altra metà, ed è un punto preciso: **un oggetto lontano non si può citare**. I campi oggi sanno solo *salire* dal punto in cui stanno (pagina che li contiene, sezione, documento); non sanno *puntare* un esempio, una figura o un paragrafo. Serve un'identità salvata per questi oggetti, e oggi non c'è: `ParagraphID` vive solo in memoria (vedi l'[esperimento Alloy](Alloy/RISULTATI.md)), e i flottanti non hanno un `id`.

## Il modello: sei concetti

Disposti dal più stabile al più calcolato.

```
STILE (definizione condivisa)
 │  dice: in quale sequenza entra, che cosa mostra, dove
 ▼
OCCORRENZA (un oggetto del documento)
 │  ha: identità, contenuto dell'autore, aggancio, eccezioni
 ▼
AGGANCIO (dove l'oggetto sta nel testo)
 │  fisso: un segno nel testo che si sposta con lui
 │  relativo: una ricerca («la quinta parola del mio paragrafo»)
 ▼
SEQUENZA (= la Lista di oggi)
 │  dà il numero: la posizione fra i suoi membri, nell'ordine
 │  degli agganci, dall'ultima ripartenza
 ▼
PRESENTAZIONE (un punto in cui l'oggetto si mostra)
 │  una formula che legge i dati dell'oggetto:
 │  segno di voce, richiamo, corpo della nota, didascalia,
 │  numero accanto al titolo, rimando, voce di indice
 ▼
COLLOCAZIONE (dove va la presentazione)
    nel testo all'aggancio · prima/dopo il paragrafo ·
    nel margine dei segni · al piede · nel margine esterno ·
    in testa alla pagina · fra le figure · in fondo · in un indice
```

**Che cosa si salva e che cosa si calcola.** Si salvano solo stili, occorrenze (identità, contenuto dell'autore, aggancio fisso o la definizione di quello relativo, eccezioni come «ricomincia da 1») ed etichette. Si calcolano numeri, pagine, collocazioni, il bersaglio di un aggancio relativo e lo stato «sospeso». Così schermo, anteprima e PDF non possono dare numeri diversi: leggono la stessa composizione.

**Dove vive l'identità.** Come segno nel testo: un attributo sul carattere che porta l'oggetto. È lo schema che in GRIFFR funziona già per il carattere del campo, l'ancora del flottante e le eccezioni alle regole (`rules-off`): segue le regole di divisione e unione del deposito, torna con Annulla e si salva con il file. Per un paragrafo, il segno sta sul primo carattere, che è proprio quello che decide l'identità nel deposito (`DocumentStore.resegment`).

**Dove vivono i dati di cento paragrafi con lo stesso stile.** Nello stile c'è *la regola*: «ogni paragrafo Esempio entra nella sequenza Esempi e mostra (n) a sinistra». Nell'occorrenza c'è *solo ciò che l'autore ha deciso per lei*: l'eventuale etichetta («pioggia») per citarla, un'eventuale ripartenza, e per una nota prodotta dallo stile il testo che l'autore vi ha scritto. Il numero di ciascuno non sta da nessuna parte: è la sua posizione.

**Aggancio e collocazione sono due cose diverse.** La nota della quinta parola ha l'aggancio nella parola (decide pagina, riga e ordine nella sequenza), la collocazione nel margine (decide dove si disegna) e un rimando altrove (una seconda presentazione dello stesso numero). Cambiare la collocazione non tocca né l'identità né il numero.

## Le differenze che restano specifiche

Il modello comune non cancella i comportamenti propri; li mette tutti nello stesso posto, la collocazione:

- **Note**: il contenuto è lungo e scritto dall'autore, può continuare alla pagina dopo (`canSplit`); la numerazione per pagina richiede di comporre più volte.
- **Figure**: si allontanano dall'aggancio secondo le posizioni ammesse (h, t, b, p); la didascalia unisce testo calcolato e testo scritto.
- **Campi**: nessun contenuto dell'autore; la loro larghezza cambia gli a capo.
- **Testatine**: si ripetono di pagina in pagina finché un'altra non prende il posto.
- **Segni delle voci**: stanno nel margine dei segni, allineati sulla punteggiatura («(9)» e «(10)»).
- **Note prodotte da uno stile** (tappa 4): l'aggancio è relativo e può mancare; il contenuto va conservato anche quando la nota è sospesa.

## Formule visuali complete

Ogni riga è una pastiglia; si legge dall'alto in basso.

**Il numero di un esempio**
```
Stile «Esempio»
  Entra nella sequenza ......... «Esempi»
  Mostra
    Questa voce
    → Numero
    → Scrivi  «(» + risultato + «)»
  Dove ......................... a sinistra del blocco, allineato a destra
```

**Un rimando a un esempio**
```
Campo
  L'oggetto con etichetta ...... «pioggia»
  → Numero
  → Scrivi risultato qui
  Se l'oggetto non c'è ......... «(??)» e un avviso
```

**Una didascalia mista**
```
Stile di flottante «Figura»
  Entra nella sequenza ......... «Figure»
  Didascalia
    «Figura » + [Questa figura → Numero] + «. »
    + [testo scritto dall'autore]
  Dove ......................... sotto l'immagine
```

**Un sottoesempio «(7a)»**
```
Sequenza «Sottoesempi»
  Ricomincia a ogni passo di ... «Esempi»
Stile «Sottoesempio»
  Mostra
    «(» + [Voce madre → Numero] + [Questa voce → Lettera] + «)»
```

**La nota della quinta parola (tappa 4)**
```
Stile «Paragrafo commentato»
  Questo paragrafo
  → Quinta parola                 (aggancio relativo)
  → Crea nota con lo stile ...... «Commento»
  Contenuto .................... scritto dall'autore, per ogni paragrafo
  Se la parola manca ........... nota sospesa, testo conservato
Stile di flottante «Commento»
  Dove ......................... margine esterno, all'altezza della parola
```

## I sette casi

**1. Un esempio su più capoversi.**
*Si salva*: il primo capoverso ha lo stile «Esempio» e, se serve, l'etichetta; i seguenti hanno uno stile di continuazione che appartiene alla stessa voce ma non conta. *Si calcola*: «(7)» è la posizione della voce. *Modificando*: spostando il gruppo, la voce cambia posizione e quindi numero; i rimandi lo seguono perché citano l'etichetta, non il numero. *L'utente vede*: il numero sul primo capoverso, e nell'ispettore «Voce 7 di Esempi, 3 capoversi». *Oggi*: la sequenza c'è; mancano il capoverso di continuazione e i rimandi.

**2. Due stili nella stessa sequenza.**
*Si salva*: i due stili indicano la stessa Lista. *Si calcola*: la posizione comune. *Oggi*: funziona già, perché la voce rimanda alla Lista per nome (`ListItem.listName`). Il formato del segno è quello della Lista; un aspetto diverso del segno per stile è un adattamento piccolo (la presentazione nello stile invece che nella Lista).

**3. Due elenchi indipendenti con lo stesso stile, e un terzo che riprende il primo.**
*Si salva*: il primo capoverso del secondo elenco porta una ripartenza («ricomincia da 1»); il primo del terzo porta «prosegue l'elenco che comincia con…» (l'identità del primo elenco). *Si calcola*: i numeri. *Oggi*: manca. `continues` vale per tutta la Lista, e non esiste una ripartenza o una ripresa puntuale. È il caso che richiede il concetto di **istanza della sequenza**.

**4. Una nota passa dal piede al margine.**
*Si salva*: la nota, il suo contenuto e il suo stile di flottante. *Si calcola*: la collocazione. *Modificando*: cambiando la collocazione nello stile di flottante cambiano tutte le note di quello stile; contenuto, numero e richiamo restano. *Oggi*: funziona già (`FloatStyle.Placement`: `pageFoot` e `outerMargin`).

**5. La quinta parola scompare e ricompare.**
*Si salva*: il contenuto della nota, sul paragrafo che la possiede (segno sul primo carattere), e nello stile la ricerca «quinta parola». *Si calcola*: il bersaglio, a ogni composizione. *Modificando*: con quattro parole la nota è sospesa ma il testo resta; aggiungendo una parola torna **una** nota, perché il contenuto è uno solo per paragrafo e per regola. Un aggancio a una parola precisa è diverso: è un segno su quella parola, e la segue se la si sposta. *L'utente vede*: nell'ispettore «Nota sospesa: il paragrafo ha 4 parole», e il comando per aprirne il contenuto. *Oggi*: da costruire (tappa 4); l'esperimento Alloy ha trovato le tre scelte da fare prima.

**6. Un oggetto in più rappresentazioni.**
*Si salva*: la figura con l'etichetta, una volta. *Si calcola*: il numero, una volta, e poi lo leggono didascalia, indice delle figure e i due rimandi. *Oggi*: la didascalia numerata c'è; mancano i rimandi e l'indice generato.

**7. Un risultato cambia l'impaginazione.**
*Si salva*: niente di più. *Si calcola*: si compone, si leggono i risultati, si ricompone finché pagine e numeri non cambiano più. *Oggi*: `PageLayout.layout` lo fa già, per le note numerate per pagina e per il numero delle pagine, con al massimo tre ripetizioni. *Da aggiungere*: un avviso quando le ripetizioni finiscono senza che il risultato si sia fermato, invece di tenere l'ultimo in silenzio.

## Che cosa c'è, che cosa va adattato, che cosa va progettato

| | Oggi | Adattamento | Da progettare |
|---|---|---|---|
| Sequenze | Liste con nome, ripartenze per lista/pagina/sezione, «1.2», simboli | Il segno come presentazione dello stile | Ripartenza e ripresa puntuali (istanze) |
| Voci | Un paragrafo = una voce | — | Voce di più capoversi |
| Note e flottanti | Un oggetto solo con stile e collocazione | Un `id` salvato | Note prodotte da uno stile (tappa 4) |
| Campi | Catene che salgono (pagina, sezione, documento) | — | Passo «l'oggetto con etichetta» |
| Identità | Sezioni e tabelle con `id`; paragrafi solo in memoria | Segno d'identità nel testo | Etichette visibili all'autore |
| Indici | — | — | Indice delle figure come presentazione collocata «in un indice» |
| Stabilità | Composizione ripetuta, al più tre volte | Avviso se non si ferma | — |

Un punto da tenere d'occhio: l'**anteprima del compositore** compone un campione suo (pagina 1, sezioni del campione), non il documento. Un numero vi apparirebbe come quello del campione, non quello dell'occorrenza scelta. O lo si dice («numero d'esempio»), o l'anteprima si compone sull'occorrenza vera.

## Tappe

Ogni tappa ha una funzione che si può provare e il caso che dimostra che il modello regge.

1. **Identità salvata e etichette.** Un segno d'identità nel testo per paragrafi e flottanti, salvato nel file; l'autore può dare un'etichetta a un oggetto. *Prova*: Salva e riapri conserva l'etichetta; dividere, unire e annullare non la duplicano (si estende il modello Alloy).
2. **Rimandi.** Il passo di campo «l'oggetto con etichetta → Numero / Pagina». *Prova*: caso 6 senza l'indice, e i rimandi del caso 1 che seguono lo spostamento.
3. **Voci di più capoversi.** Capoversi di continuazione nella stessa voce. *Prova*: caso 1 completo.
4. **Ripartenze e riprese puntuali.** «Ricomincia da…» e «prosegue l'elenco…» sull'occorrenza. *Prova*: caso 3.
5. **Il segno come presentazione dello stile.** «Questa voce → Numero» nelle formule degli stili; il numero accanto al blocco diventa una formula come quelle delle testate. *Prova*: caso 2 con aspetti diversi del segno, e il sottoesempio «(7a)».
6. **Note prodotte da uno stile.** La tappa 4 del piano, con le scelte dell'esperimento Alloy. *Prova*: caso 5.
7. **Indice delle figure.** Una collocazione «in un indice» che raccoglie una presentazione per ogni figura. *Prova*: caso 6 completo.

Le tappe 1 e 2 vengono prima perché tutte le altre ne hanno bisogno per citare un oggetto. La 3 e la 4 sono indipendenti fra loro.

## Decisioni editoriali · prese il 7 novembre

- **Continuazione di una voce**: un **interruttore sul capoverso** («continua la voce precedente»); lo stile resta quello della voce. Nel caso 1, i capoversi seguenti restano «Esempio» con l'interruttore acceso, e l'ispettore lo mostra.
- **Un elenco nuovo con lo stesso stile**: **dipende dalla Lista**, come oggi (`continues`): gli elenchi comuni ricominciano dopo un paragrafo di altro stile, gli esempi proseguono. In più, sul capoverso, i comandi «Ricomincia da…» e «Riprendi l'elenco…».
- **Etichette**: si sceglie l'oggetto **con un clic** (o da un elenco); GRIFFR propone un nome leggibile tratto dal testo, che l'autore può cambiare.
- **Rimando a un oggetto cancellato**: **«(??)» nel testo e un avviso** nell'elenco degli avvisi.
- **Nota della quinta parola**, le tre scelte dell'[esperimento Alloy](Alloy/RISULTATI.md):
  - unendo due paragrafi con una nota ciascuno, **i due testi si fondono** in una nota sola, con un avviso; GRIFFR **ricorda il punto** in cui cominciava il secondo;
  - spezzando il paragrafo prima della quinta parola, la nota **resta al primo, sospesa**, e torna quando il paragrafo ha di nuovo cinque parole; il paragrafo nuovo ha una nota sua, vuota;
  - togliendo un a capo e riscrivendolo a mano nello stesso punto, **la nota del secondo torna**: grazie al punto ricordato, le due note si separano di nuovo.

  - dopo un'unione, spezzando il paragrafo prima delle parole che erano del secondo, **la parte di nota del secondo segue quelle parole** nel paragrafo nuovo.

Verificato con Alloy ([esperimento 2](Alloy/RISULTATI.md#esperimento-2--la-regola-fondi-e-ricorda-il-punto)). Come realizzarlo: il testo di ogni nota porta un segno sul primo carattere del suo paragrafo; cancellando un carattere con un segno, **il segno passa al carattere che segue** (altrimenti si perde testo); i segni sullo stesso carattere **ricordano il loro ordine** (altrimenti, nel caso di un paragrafo vuoto, riscrivere l'a capo non separa le note). Verificato anche questo, nei limiti di due note.

## Scelte tecniche consigliate

- **Identità come segno nel testo**, non come numero in memoria: segue già le regole di divisione, unione e Annulla del deposito, e si salva con il file.
- **Numeri mai salvati**: si calcolano componendo, come oggi per Liste e note; così schermo, anteprima e PDF non possono divergere.
- **Una sola passata di numerazione** che servono tutte le presentazioni: segno, richiamo, didascalia, rimando e indice leggono lo stesso valore.
- **Composizione ripetuta con limite e avviso**, come oggi ma senza silenzio quando non si stabilizza.
- **Le Liste restano il nome visibile delle sequenze**: il concetto esiste già nell'interfaccia e nel formato; si estende, non si sostituisce.
