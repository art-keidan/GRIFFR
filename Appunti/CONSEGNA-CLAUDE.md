# Consegna a Claude · compositore di stili ad azioni

## Obiettivo scelto dall'utente

Adottare nell'app nativa GRIFFR l'interfaccia del prototipo `Interfaccia-formule/prototipo-automator.html`, ispirata ad Automator di macOS. L'interfaccia attuale è troppo affollata: ogni nodo dell'espressione introduce un riquadro, un menu e una rientranza; proprietà, condizioni, parametri e risultati si sovrappongono visivamente.

L'utente vuole proseguire questo lavoro con Claude. Questa consegna trasferisce il contesto dal precedente lavoro in Codex; il prototipo è stato approvato come direzione. Non serve ripartire proponendo un'altra famiglia di interfacce.

## Materiale da aprire

- `Interfaccia-formule/prototipo-automator.html`: versione completa apribile in un browser. È autonoma rispetto alla conversazione; la visualizzazione delle icone può richiedere le risorse pubbliche del renderer.
- `Interfaccia-formule/prototipo-automator.fragment.html`: sorgente originale dell'anteprima approvata, utile per leggere struttura, interazioni e adattamento della larghezza.
- `RIASSUNTO-RESIDUO.md`: piano funzionale corrente.
- `FORMULE-RIUTILIZZABILI.md` e `prova-formule-riutilizzabili.grx`: funzione già realizzata, istruzioni e campione persistente.
- `VISIONE.md`, `CATALOGO-OPERAZIONI.md`, `ARCHITETTURA-PROPOSTA.md`: contesto di lungo periodo, non elenco di funzioni già disponibili.

Il codice del prototipo è dimostrativo: mostra tre azioni, riferimenti e valori predefiniti. Non è il nuovo modello del documento. Non trasferire ciecamente le sue limitazioni nell'app. Le modifiche fatte dall'utente provando il mockup (rimozione di un'azione, numeri o stile precedente) sono prove transitorie, non richieste di togliere funzioni.

## Disegno approvato

Una finestra del compositore con tre aree ridimensionabili:

1. **Libreria a sinistra.** Azioni raggruppate per selezione/condizioni, calcoli e formattazione; accesso alle formule del documento. Ricerca delle azioni. Aggiunta mediante comando esplicito; il trascinamento può affiancarlo.
2. **Flusso al centro.** Oggetto iniziale e sequenza di azioni. Ogni azione ha titolo, icona sobria, controlli per espandere/richiudere, spostare e rimuovere. Nel corpo solo parametri necessari. Quando chiusa, una riga descrive cosa fa. Le formule riutilizzabili appaiono come un'azione nominata con argomenti; la definizione si apre solo su richiesta.
3. **Anteprima a destra.** Campione tipografico, contesto di prova, risultato e diagnosi. Un comando Prova rivaluta il campione; Applica al documento conserva la semantica di bozza e aggiornamento già esistente.

I risultati nominati sono variabili riconoscibili e selezionabili negli ingressi compatibili: per esempio il calcolo produce **Distanza**, poi un'azione imposta il rientro sinistro a **Distanza**. Mostrare testo e tipo in modo comprensibile, senza affidarsi soltanto ai colori.

La leggibilità viene prima della decorazione. Una superficie per azione, niente scatole ricorsive per ogni costante e operando. Dettagli avanzati e definizioni annidate si aprono al bisogno. Conservare il tema dell'app e la cura tipografica nativa.

## Semantica da rispettare

L'aspetto è quello di un editor visuale di script, ma gli stili rimangono dichiarativi e si aggiornano durante scrittura e composizione. Non imporre all'autore di eseguire manualmente uno script per applicare uno stile.

Le fasi già definite in `StyleConditions.swift` sono un vincolo reale: ordinare nella stessa fase è diverso dal trascinare una direttiva strutturale in una fase di resa. Riutilizzare i controlli/diagnosi del modello, impedire spostamenti non validi oppure spiegarne il motivo. Non eliminare le fasi per imitare il flusso lineare del mockup.

Le condizioni e i destinatari continuano a riferirsi alla formula corretta. Una condizione visiva non deve diventare per errore un filtro globale per tutte le azioni successive. La libreria deve consentire di configurare i casi già supportati: condizione a inizio pagina, predecessore, misure naturali, parti del paragrafo, selezioni condivise, tenuta, apertura di sezione e stile dopo Invio.

Per le formule riutilizzabili conservare identità e parametri tipizzati, chiamate e argomenti, somme, numeri/lunghezze/booleani, collegamenti alle proprietà, limiti di espansione e diagnosi dei cicli. Se la rappresentazione di variabili/passaggi richiede un adattatore, deve ricostruire la stessa definizione autorevole; non creare un secondo modello indipendente usato soltanto dalla schermata.

Se un nuovo stato dell'interfaccia richiede persistenza, scegliere uno schema versionato e testarne l'andata e ritorno. Non cambiare formato per sole preferenze di espansione o disposizione della finestra se non serve.

## Mappa del codice

- `Sources/WordProcessor/StyleComposer.swift`: finestra, `ComposerBoardModel`, sezioni Stili/Selezioni/Regole/Formule, bozza, validazione, applicazione e anteprima. È il principale punto di sostituzione dell'interfaccia.
- `Sources/WordProcessor/ReusableFormulaEditor.swift`: editor ricorsivo attuale delle espressioni e delle definizioni; causa principale delle scatole annidate da riprogettare.
- `Sources/WordProcessor/WindowBands.swift`: `Theme`, colori e stile dell'app.
- `Sources/WordProcessor/EditorWindowController+Stili.swift`, `InspectorPanel.swift`: integrazione dei controlli e provenienza; protezione dei calcoli dalla sostituzione involontaria con costanti.
- `Sources/Typesetting/ReusableFormula.swift`: tipi, parametri, definizioni, validazione e valutazione.
- `Sources/Typesetting/ReusableFormulaIntegration.swift`: risoluzione dei collegamenti, codifica, riepiloghi e diagnosi.
- `Sources/Typesetting/StyleFormula.swift`, `StyleConditions.swift`, `StyleFormulaControls.swift`, `StyleRuleCompilation.swift`: formule di stile, fasi, collegamenti ai controlli, regole contestuali.
- `Sources/Typesetting/DocumentFormat.swift`: XML fino alla versione 11.
- `Sources/Typesetting/DefinitionImport.swift`: dipendenze e conflitti in incolla/importazione.
- `Sources/WordProcessor/TextDocument.swift`: lettura/scrittura e protezione dell'originale quando aumenta il formato.

## Criteri di completamento

- Un documento nuovo e i campioni esistenti aprono il nuovo compositore. Il percorso per gestire stili, selezioni, regole storiche e formule riutilizzabili resta accessibile.
- Si possono creare, configurare, richiudere, riaprire, spostare e rimuovere azioni, rispettando tipi e fasi. Le diagnosi indicano l'azione interessata e una correzione comprensibile.
- Il caso «Base 12 pt + margine 6 pt → Distanza → rientro sinistro» è costruibile dalla UI e produce 18 pt. Portare il margine a 10 produce 22 pt sulle occorrenze dello stile.
- Le definizioni e i parametri si possono rinominare senza interrompere le chiamate. Riutilizzo in più stili, importazione con identità in conflitto, cicli e argomenti mancanti restano gestiti.
- Anteprima, Applica, Annulla/Ripeti, controlli ordinari e ispettore concordano. Una bozza non sovrascrive silenziosamente cambiamenti fatti altrove.
- Salvataggio e riapertura conservano definizioni e resa, senza duplicazioni e con lettura dei file precedenti.
- Finestra ridimensionabile: i controlli non spariscono a larghezze contenute e le formule lunghe non causano crescita illimitata della finestra. Navigazione e spostamento delle azioni sono possibili da tastiera, anche senza trascinamento. Etichette VoiceOver e contrasto adeguati.
- Prove pertinenti eseguite, verifica visiva nativa quando disponibile e `build/GRIFFR Stili.app` ricreata. Dichiarare con precisione ciò che non si è potuto verificare.
- Aggiornare `RIASSUNTO-RESIDUO.md` e il resoconto del revamp; nessuna funzione dimostrativa con valori finti nell'app finale.

## Prove da cui partire

`Tests/WordProcessorTests/ReusableFormulaEditorTests.swift`, `FormulaControlTests.swift`, `RealStyleBoardTests.swift`, `ContextStyleEditorTests.swift`; `Tests/TypesettingTests/ReusableFormulaTests.swift`, `StyleContextFormulaTests.swift`, `StyleFormulaTests.swift`.

Le prove recenti del percorso selezionato erano 14 nell'editor e 13 nel motore, più una prova sul campione distribuito: 28 passate. È un punto di partenza registrato, non un sostituto della verifica dei nuovi cambiamenti. Il controllo visivo con l'automazione di Codex era andato in timeout; non va presentato come già superato.

Le istruzioni di build locali sono in `CLAUDE.md`. Lo script confeziona una sola applicazione corrente e conserva le precedenti come `.retired`.

## Dopo il revamp

Il lavoro successivo resta nell'ordine del piano: estendere Posizione/campi/Scrivi risultato; testate di capitolo; flottanti derivati e relazioni fra oggetti; migrazione di tabelle/celle/flottanti; verifica d'uso/accessibilità. Le estensioni tipografiche indipendenti vengono dopo. Non iniziare queste funzioni nel corso del revamp senza una nuova richiesta.
