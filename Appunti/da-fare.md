# Cose da fare

Elenco unico, rivisto il 2 novembre 2026 rileggendo tutti gli Appunti e controllando nel codice. Prende il posto dei
piani precedenti, che erano conclusi o avevano solo pochi punti aperti (vedi in fondo come recuperarli). Ogni voce
dice da dove viene; dove serve, se lo stato è **provato**, **letto** nel codice o **supposto**.

## 1. Il motore tipografico: le proposte rimaste della parte B

Dal piano del 1 novembre 2026, che riprendeva la proposta del fork «GRIFFR Lab». La parte A (tenuta delle righe) e B1
(sporgenza della punteggiatura negli a capo) sono fatte. Le altre restano proposte separate, da scegliere una per
volta.

- **B2. Tabulazioni nel compositore ottimale.** Oggi un capoverso con una tabulazione rinuncia alla scelta ottimale
  degli a capo e si compone riga per riga (letto: `LineBreaker.optimalBreaks` restituisce `nil`). Proposta del Lab:
  trattare la tabulazione come un salto fino al prossimo arresto, senza a capo subito prima o dopo. Più costosa di
  quanto il Lab scriveva: la larghezza di una tabulazione dipende da dove comincia la riga, quindi non si legge una
  volta per tutte dalla riga non spezzata. Utile solo con tabulazioni in capoversi giustificati lunghi. Prima di
  cominciare: contare nei documenti veri quanti capoversi la usano.
- **B3. Griglia delle linee di base.** Le righe cadono a multipli di un passo fisso, alla stessa altezza su tutte le
  pagine e sulle pagine affiancate. Buona per i libri; da ragionare con note, titoli, spazi prima e dopo, figure e
  tabelle, che oggi spostano le righe di quantità qualsiasi. Prima di cominciare, decisioni dell'utente: se serve ai
  suoi lavori; passo e partenza; se vale per tutto il documento o per stile (i titoli fuori griglia?).
- **B4. Spaziatura fra le lettere nella giustificazione.** Allargare un poco anche lo spazio fra le lettere, oltre a
  quello fra le parole. Ultima per priorità: la deformazione dei glifi c'è già (limite nel documento), e spaziare le
  minuscole è discutibile.
- **B5. Testo da destra a sinistra nel compositore ottimale.** Oggi arabo ed ebraico si compongono riga per riga
  (letto: il compositore rinuncia appena trova un tratto da destra a sinistra). Solo se servono queste scritture.

Escluse, come nella proposta e nelle decisioni fisse del progetto: HarfBuzz al posto di Core Text, Vello, Rust o
Tectonic, cornici concatenate.

Sulla B1, per memoria (provato il 2 novembre): la sporgenza viene dalla tabella `opbd` del font, e fra i font
installati ce l'hanno solo Hoefler Text e Apple Chancery; l'effetto misurato è piccolo (6 capoversi su 100 cambiano).

## 2. Il motore tipografico: idee più grandi (28 ottobre 2026)

- **La pagina intera.** Scegliere gli a capo guardando anche il risultato della pagina (niente buchi vistosi in
  fondo), senza peggiorare sensibilmente i singoli capoversi.
- **Regole tipografiche per lingua**, distinte da sillabazione e ortografia, anche per variante nazionale: in
  italiano e in inglese niente parola di una lettera in fine riga; in francese spazi inseparabili (sottili) dentro
  «» e prima di ; ? ! e : (Québec diverso); in spagnolo ¿…? e ¡…! attaccati; in ceco, slovacco e polacco preposizioni
  di una lettera legate alla seguente, e numero con unità, date, abbreviazioni. Il motore deve rappresentare divieti di
  a capo e spazi inseparabili di larghezze diverse, non sostituire caratteri nel testo. Riferimenti iniziali: Antidote
  (spazi inseparabili francesi, Francia e Québec), JoliCode (microtipografia francese), Foro Alfa (regole RAE su ¿ ¡),
  l'issue 7469 di Typst (polacco), Microsoft Learn (ceco e polacco).

## 3. Oggetti, rimandi, struttura

Dal disegno a oggetti (fasi 1–7 fatte: stili, Liste, ispettore, deposito del documento, flottante unico, tabelle,
regole con proprietà dinamiche) e dalle idee del progetto parallelo di ChatGPT.

- **Rimandi a un oggetto preciso** («vedi nota 3», «fig. 2 a pagina 14»), che leggono numero e pagina e si aggiornano
  da soli. Richiedono ancore stabili nel file: un punto del testo che segue le modifiche, cade sempre fra due grafemi e,
  se il testo sparisce, resta segnalato invece di riattaccarsi da solo. Servono anche per lemmi delle note e commenti.
  Oggi ci sono solo i campi relativi (pagina, totale delle pagine, titolo e numero della sezione in corso: letto).
- **Indice generato da una Lista** (di solito quella dei titoli): non c'è (letto).
- **Note di chiusura alla fine della sezione**: oggi vanno solo alla fine del documento (letto: nessun posto «fine
  della sezione» fra quelli dei flottanti).
- **Regole**: una regola che dà un valore singolo senza uno stile («una regola nuova» dall'ispettore); la riga come
  oggetto con proprietà proprie per regola (allineamento dell'ultima riga, numero di riga a margine); il capolettera
  su più righe.
- **Colonne di pagina**: non ci sono (letto).
- **Da decidere:** che cosa fa una Lista finita oltre il suo ultimo valore (oggi il programma lo chiede ogni volta);
  che cosa succede quando due flottanti vogliono lo stesso posto, oltre alle note a margine (lì le sovrapposizioni si
  segnalano e restano).
- **Domanda aperta dall'inizio:** gli oggetti servono solo per l'aspetto, o devono portare informazioni proprie (una
  parola con glossa, lemma, traduzione, composti allineati sotto come nei testi glossati interlineari)? Proposta
  rimasta in sospeso: la parola normalmente si trova; diventa un oggetto salvato solo quando le si dà qualcosa di suo.

## 4. Sezioni e livelli (1 novembre 2026)

- «Più dentro» e «Più fuori» dall'ispettore non tengono conto dei ritorni alla sezione esterna: un ritorno a una
  sezione che non la contiene più si toglie.
- Dare un livello a uno stile non trasforma in titoli i capoversi del corpo che lo usano.
- Il livello «Nessuno» di uno stile non toglie le sezioni.

## 5. Interfaccia

- **Font di ripiego scelti dall'utente** (29 ottobre 2026): per lingua, per scrittura, per zona Unicode, per font
  scelto. Da decidere: se le preferenze sono dell'applicazione o anche del documento; l'ordine (font scelto → lingua →
  scrittura → zona → macOS); come le mostrano schermo, PDF e ispettore.
- **Accessibilità**: la vista delle pagine è opaca per VoiceOver (testo, selezione, righe); segmenti delle fasce,
  pastiglie del monitor degli stili e righello non si usano dalla tastiera né si leggono (letto: nessun codice di
  accessibilità). Dalle revisioni di KIMI (26 ottobre) e del 31 ottobre. Ha senso soprattutto se il programma servirà
  ad altri.
- **Testi e bersagli più grandi** nei controlli (revisione di KIMI).
- **Un «⋯» per i comandi della barra che non entrano** nella finestra stretta (revisione di KIMI). La larghezza minima
  secondo i pannelli è fatta.
- **Modalità scrittura** (⇧⌘F nasconde i pannelli e poi li rimette) e **scorciatoie per le schede del pannello**
  (⌘1…): idee del progetto parallelo, non fatte (letto).
- **Anomalia vista il 19 ottobre:** l'app si è aperta nell'interfaccia semplice senza che la si cambiasse. Causa non
  trovata; non più vista da allora (supposto: nessuna nota successiva).

## 6. Robustezza

- **Recupero dopo un arresto**: il salvataggio automatico è spento (letto: `autosavesInPlace` falso) e non c'è
  recupero. Idea del progetto parallelo: copie di sicurezza periodiche, senza riscrivere il file originale.

## 7. Da provare a schermo

Funziona nelle prove automatiche, ma non è stato guardato nell'app:

- Sezione: i controlli di ispettore e scheda Pagine (pagina dispari, distanza d'apertura, capitoli numerati «1.»,
  «2.», pagina orizzontale fra verticali); la stampa con formati di pagina misti.
- Livelli: la riga «Livello» della scheda Stili; nella mappa, l'apertura di un titolo chiuso passandoci sopra e lo
  scorrimento al bordo durante il trascinamento.
- Intestazioni: le schede Flottanti e Liste, Inserisci › Campo, l'ispettore.
- Tabelle: Maiuscole+Tab, Opzione+Tab, Invio in una cella, incollare, le righe d'intestazione cambiate
  dall'ispettore; la tabella flottante rimandata in cima a una pagina dopo o in una pagina a parte.
- Tenuta delle righe: le quattro voci nella scheda Stili; un titolo «tieni col seguente» seguito da una figura «qui».
  Limite noto: una figura in fondo alla pagina richiamata a metà di un capoverso.

## 8. Da verificare con una prova

Segnalazioni del progetto parallelo, mai controllate da noi:

- Con la sillabazione spenta, il compositore preferisce righe quasi vuote? (supposto che no; da provare con un
  capoverso giustificato senza sillabazione).
- Il trattino di sillabazione non deve entrare nel testo salvato né in quello copiato (supposto che sia già così).

## 9. Decisioni che restano valide

- Core Text; AAT prima di OpenType; PDF di sistema; niente docx, HarfBuzz, Typst. Graphite solo se `graphite2` è
  installata nel sistema; se manca, Core Text con un avviso, e la scelta resta nel documento.
- `GSUB` al posto di `morx` in un font che li ha tutti e due: si resta con l'automatismo di macOS (provato su
  Vulcanius il 14 ottobre che si potrebbe, con una copia del font in memoria).
- Tenuta delle righe solo a richiesta (stile o capoverso), minimi indipendenti in fondo e in cima.
- Sporgenza della punteggiatura negli a capo dove ci sono i margini ottici, senza interruttore nuovo.

## Il progetto, con le parole dell'utente (14 ottobre 2026)

> Voglio un word processor che sia versatile come LaTeX, ma totalmente GUI. Non devo essere costretto a scrivere del
> codice. Ma devo poter modificare tutti gli aspetti del prodotto finale. Voglio che il mio documento sia una struttura
> a oggetti; ogni oggetto deve avere tutte le proprietà modificabili, deve essere legato ad altri oggetti ecc. Alcuni
> oggetti sono statici (ad esempio, il paragrafo); altri sono dinamici (ad esempio: la prima riga del paragrafo).
> Alcuni oggetti devono poter essere inseriti come elementi flottanti, ossia: le note a piè di pagina, le immagini, ma
> anche, ad esempio, le note a margine; anzi, probabilmente vale la pena creare un unico tipo «flottante», che poi
> diventerà footnote o margin note, o image, secondo le impostazioni che gli si settano. Ovviamente l'utente base deve
> poter disporre di un buon default: deve poter usare il programma come un MS Word; ma se vuole, può cominciare a
> modificare i default.

## Riferimenti

- Elenco degli oggetti, una scheda per oggetto: <https://claude.ai/artifact/2thkiU2dioqrsxFxZfWrR4> (privata).
- Disegno dell'interfaccia (tappa I.0): <https://claude.ai/artifact/Gt63SXf6Vgcx3dPoWvZwkS> (privata).
- In questa cartella restano anche:
  - [comportamenti-scrittura.md](comportamenti-scrittura.md): che cosa sa fare la scrittura, voce per voce; le prove
    di `EditingBehaviourTests` portano il numero della voce.
  - `annapurna-sil-tabelle.wpx`: il documento di prova sulle tabelle Graphite dei font di Annapurna SIL.

## I piani conclusi, tolti il 2 novembre 2026

Erano: `LEGGIMI.md`, `disegno-oggetti.md`, `testo-come-oggetti.md`, `interfaccia.md`, `graphite.md`, `sezione.md`,
`fine-sezione.md`, `intestazioni.md`, `tabelle.md`, `idee-progetto-parallelo.md`, `funzionalità-future.md`,
`motore-tipografico-piano.md`, `proposta-motore-tipografico.md` e la cartella `revisione-2026-10-18` (i sei difetti
segnalati sono tutti corretti). Contengono la storia delle scelte e delle tappe; si rileggono dall'ultimo commit che
li ha, per esempio:

```bash
git show 4f09de4:Appunti/sezione.md
```
