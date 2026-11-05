# Terza tappa · Gli stili reali nella bacheca

4 novembre 2026

La bacheca ora apre gli stili di paragrafo, parola e carattere del documento. Ogni stile mostra la base ereditata e le proprie formule ordinate. I pulsanti e le pills conservano il tema dell'app; la finestra resta indipendente e ridimensionabile.

## Come provarla

1. Aprire **build/GRIFFR Stili.app** e il [campione della bacheca](prova-bacheca-stili.grx).
2. Scegliere **Formato → Compositore di stili… → Stili del documento**.
3. Selezionare **Forte**. Le pills mostrano **Aggiungi · Font · Grassetto**.
4. Con **Carattere di partenza · Corsivo**, leggere ingresso e risultato e osservare il campione.
5. Cambiare la prima pill in **Imposta**: il campione diventa grassetto tondo.
6. Scegliere **Applica al documento**: cambia anche la parola marcata Forte nel documento. **Annulla** e **Ripeti** ripristinano definizione e testo insieme.
7. In **Citazione relativa**, cambiare **Aggiungi · Rientro sinistro · 6 pt** in **Imposta**. Il risultato passa da 30 a 6 pt, perché lo stile di base fornisce 24 pt.
8. Salvare e riaprire. Se il documento proviene da un formato precedente, il primo aggiornamento richiede una copia, conservando l'originale.

**Selezioni condivise** mantiene le schede già disponibili per raccogliere parole e collegare trattamenti.

## Formule modificabili

Le proprietà offerte sono ruolo del font, famiglia, corpo, colore, maiuscoletto, lingua, sillabazione, allineamento, spazi prima e dopo, rientri e spazio fra righe. Il tipo dello stile filtra le proprietà ammesse. Il menu del predicato offre Imposta e, dove definiti, Aggiungi e [Sottrai](SOTTRAI.md).

Le misure accettano pt, mm, cm, in e pc. Ogni riga mostra il valore ricevuto e quello prodotto sul campione. Le formule si possono aggiungere, rimuovere e riordinare. Il menu della base offre i genitori compatibili, escludendo i cicli.

La conversione dei valori storici supportati avviene nella bozza quando si seleziona uno stile. Una dichiarazione storica di grassetto attivo diventa Aggiungi Font Grassetto, conservando il corsivo ricevuto. Applica registra la bozza, ricompone il testo e aggiorna la base di confronto della bacheca. Se nel frattempo gli stili sono cambiati altrove, l'applicazione si ferma con una richiesta di ricaricamento; il documento mantiene le modifiche più recenti.

## Compatibilità e perimetro

Le scelte avanzate del font e i tratti esplicitamente disattivati restano dichiarazioni compatibili. In presenza di scelte avanzate ereditate, anche le relative dichiarazioni di famiglia e tratti restano nel percorso storico. I campi storici del font si fondono secondo le vecchie precedenze fino a incontrare un predicato esplicito Font o Famiglia; formule su corpo e spazi non devono alterare questa fusione.

Le altre proprietà non ancora convertite sono segnalate nella scheda come **Altre proprietà conservate**. Tenuta, liste, apertura di sezione, variante di inizio pagina, decorazioni, assi e funzioni tipografiche rimangono modificabili dai controlli già esistenti. Tabelle, flottanti, condizioni e campi appartengono alle tappe successive.

Gli argomenti famiglia, colore, maiuscoletto e sillabazione richiedono il formato **5**. I documenti con le sole formule precedenti possono rimanere nel formato 4. Identità e ordine sopravvivono alla riapertura. La base del documento rimane stabile per le operazioni relative.

## Verifiche

Le prove coprono la modifica effettiva di Forte, Annulla/Ripeti e riapertura, la resa dei tredici stili predefiniti sui quattro ruoli del font, la conversione ripetuta senza duplicazioni, le scelte avanzate ereditate, ingressi e uscite del rientro e il rifiuto di una bozza basata su definizioni superate.

La suite completa ha superato le 190 prove dell’editor presenti in quella corsa. Le 466 prove del motore riportano le stesse 20 segnalazioni del riferimento, senza nuove segnalazioni; riguardano i font di prova mancanti. Dopo l’ultimo controllo delle bozze non valide, le 16 prove mirate sono tutte passate (6 dell’editor e 10 del motore). Il campione nuovo si apre, si impagina e si riscrive. Il riferimento Annapurna conserva XML identico e le stesse coordinate per tutte le 104 righe.

La verifica visiva manuale della finestra resta da svolgere: in questa sessione sono disponibili compilazione e prove dell'editor, senza controllo diretto dell'interfaccia macOS.

[Implementazione della bacheca](../Sources/WordProcessor/StyleComposer.swift) · [Conversione](../Sources/Typesetting/StyleFormulaMigration.swift) · [Prove](../Tests/WordProcessorTests/RealStyleBoardTests.swift) · [Piano](PIANO-STILI-FORMULE.md)
