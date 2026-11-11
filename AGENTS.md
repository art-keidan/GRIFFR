# GRIFFR · contesto per Codex

Questa cartella è l'unico progetto di lavoro: `/Users/artemio/GRIFFR`.
L'app nativa macOS usa Swift Package Manager, AppKit, SwiftUI e Core Text. Il prodotto si chiama GRIFFR; la copia di sviluppo è `build/GRIFFR.app`.

## Lavoro attuale autorizzato

L'utente ha scelto il prototipo del compositore con azioni in sequenza ispirato ad Automator. Leggi prima `Appunti/CONSEGNA-AGENTS.md`, poi il prototipo locale e i sorgenti indicati. La consegna descrive un'implementazione completa da realizzare in SwiftUI/AppKit, con prove, aggiornamento degli appunti e ricompilazione della .app.

Il piano generale resta in `Appunti/RIASSUNTO-RESIDUO.md`. Il revamp dell'interfaccia viene prima delle tappe funzionali residue. Gli appunti in `Appunti/archivio/` sono storici.

## Stato del repository

Il branch locale è `main`. Molto lavoro valido è modificato o non ancora tracciato da Git: anche i nuovi modelli, editor e test delle formule. Il working tree è la sorgente autorevole per il passaggio di consegne. Leggi `git status` e preserva tutti questi file. Non ricostruire il progetto dal solo commit e non usare reset, checkout dei file, clean o stash per eliminare le modifiche. Non creare commit, pubblicare o modificare remote senza richiesta.

## Architettura e vincoli

- `Sources/Typesetting`: modello, risoluzione degli stili, formule, formato XML, impaginazione, font e PDF.
- `Sources/WordProcessor`: interfaccia ed editor nativi. Usa il tema esistente in `WindowBands.swift`.
- Il formato corrente è la versione 18, ed è anche la più vecchia che il programma legge (`DocumentFormat.oldestReadableVersion`): l'8 novembre è stata tolta la retrocompatibilità con le versioni dello sviluppo, con i campi storici, i nomi italiani dei documenti di prima, le regole del documento (ora solo formule contestuali degli stili) e l'estensione `.wpx`. Un costrutto nuovo alza `version`; le versioni successive devono continuare a leggere la 18. Il revamp grafico dovrebbe riutilizzare il formato esistente; valuta esplicitamente eventuali nuovi costrutti prima di introdurli.
- Le azioni rappresentano definizioni dichiarative. Il motore distingue resa di base, collocazione, contesto, composizione naturale e azioni dell'editor. L'aspetto di Automator non autorizza a trasformare tutto in uno script procedurale.
- Annulla/Ripeti, bozze concorrenti, ereditarietà, importazione e provenienza fanno parte del comportamento da preservare.
- Il prototipo HTML è un riferimento di progettazione. Non inserirlo nell'app come WebView.
- Bundle identifier `local.griffr`, tipo dei documenti `local.griffr.document`, estensione `.grx` (8 novembre). Non alterarli senza richiesta.

## Compilazione e verifiche

Esegui dalla radice del progetto. In questo ambiente funzionano le cache locali e il sandbox dei subprocessi di SwiftPM disabilitato:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" SWIFT_MODULE_CACHE_PATH="$PWD/.build/swift-module-cache" swift test --disable-sandbox --filter 'ReusableFormula|FormulaControlTests|RealStyleBoardTests|StyleContextFormulaTests|ContextStyleEditorTests'
```

Confeziona l'app dopo le prove:

```sh
GRIFFR_DISABLE_BUILD_SANDBOX=1 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" SWIFT_MODULE_CACHE_PATH="$PWD/.build/swift-module-cache" Scripts/build-app.sh
```

Il generatore dei simboli Release può richiedere permessi che il sandbox esterno blocca. Segui il normale flusso di autorizzazione dello strumento; non aggirare le protezioni. I precedenti test segnalavano font di prova mancanti nelle suite complete: distingui problemi preesistenti e regressioni, senza nascondere errori.

Comunica in italiano, completa il percorso autorizzato e descrivi esattamente prove eseguite, risultato e limiti di verifica visiva.
