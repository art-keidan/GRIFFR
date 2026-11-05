# Distanza del capoverso a inizio pagina

Nella scheda **Stili** dell'interfaccia dettagliata, scegliere uno stile di paragrafo. In **Quando apre la pagina** scegliere **Distanza** e scrivere, per esempio, 30 mm. **Eredita** usa la scelta dello stile di base. **Disattivata** sospende la variante ereditata. Una distanza esplicita di zero è un valore attivo. Il controllo **Distanza d'apertura** già esistente continua a regolare l'apertura di sequenza.

La nuova distanza vale per il blocco del capoverso nel corpo principale. Il compositore la rivaluta dopo un salto naturale e dopo lo spostamento del titolo insieme al suo seguito. Il distacco locale applicabile all'apertura di una sequenza ha precedenza. L'ispettore del paragrafo riporta il nome dello stile e la distanza effettiva e richiesta quando interviene la variante. La prima versione riguarda i capoversi del corpo. Celle, contenuti delle note e la riga del cursore ancora vuota in fondo al documento seguono i propri percorsi di composizione.

[Documento di esempio con due titoli dello stesso stile](prova-apertura-pagina.grx)

## File

Una definizione contestuale, anche disattivata, richiede il formato 2. Il documento conserva la versione 2 una volta riaperto. Per un file v1 che acquista una variante, Salva propone un nuovo nome. La protezione al momento della scrittura impedisce di scegliere l'originale come destinazione. Il file v2 contiene la scelta dell'autore. La pagina e la distanza effettiva si ricalcolano all'apertura.

## Riscontri del 4 novembre 2026

- Ambiente di riferimento macOS 27.2 arm64, Swift 6.4.2, revisione di partenza del fork 28aed35. Le cinque nuove prove automatiche passano. Coprono salto naturale e spostamento per tenuta, riduzione del distacco in una pagina corta, ereditarietà e XML, protezione del file originale e percorso dello stile nell'editor con Annulla, Ripeti, riapertura e misura del testo nel PDF tramite PDFKit.
- Suite completa. Nella corsa finale l'editor riporta 184 test e supera la suite. Il motore riporta 455 test e 20 segnalazioni, già presenti nella corsa di riferimento su 453 test. Fra i problemi dell'ambiente ricorre il font di prova Vulcanius, non reperibile al percorso atteso. Nessuna nuova segnalazione fra le due corse. Alcune prove dipendenti dai font sono saltate dal runner.
- Controllo nella finestra del fork sul documento di esempio. Il primo titolo risulta primo della pagina 1 e nel dettaglio «Apertura pagina» appare lo stile «Titolo di capitolo», con 85 pt effettivi e 85 pt richiesti (30 mm arrotondati per la visualizzazione).
- Confronto indipendente sul campione Annapurna v1, usando il modulo compilato del progetto originale e quello del fork. L'XML riscritto coincide byte per byte. Per tutte le 104 righe coincidono pagina, intervallo del testo, origine e larghezza. Il lettore precedente riapre l'XML prodotto dal fork con lo stesso impaginato.

[Prove del motore](../Tests/TypesettingTests/KeepWithNextTests.swift) · [Prove dell'editor e del formato](../Tests/WordProcessorTests/PageStartSpacingTests.swift) · [Piano di migrazione](MIGRAZIONE.md)
