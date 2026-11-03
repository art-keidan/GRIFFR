# Identità dell'applicazione

Il nome da mostrare agli utenti è **GRIFFR**, tutto maiuscolo. «Griffer» è una denominazione precedente e non va utilizzata nell'interfaccia.

## Immagini

- `riferimento_approvato.png`: immagine originale approvata, con sfondo grigio esterno; è il riferimento visivo.
- `icona_trasparente.png`: adattamento isolato dell'icona, con trasparenza esterna. È una rielaborazione del riferimento, non un ritaglio identico; controllarne i bordi prima della distribuzione.
- `GRIFFR.iconset/`: le dimensioni macOS generate dall'adattamento.
- `GRIFFR.icns`: icona pronta per il bundle macOS, ottenuta dalle immagini dell'iconset e verificata mediante estrazione con `iconutil`.

## Indicazioni per l'integrazione

Il progetto usa Swift Package Manager e `Scripts/build-app.sh` crea `build/WordProcessor.app` con un Info.plist generato nello script. Per applicare il marchio, verificare il codice e aggiornare i nomi visibili, il nome del bundle e l'icona. È possibile mantenere il nome tecnico dell'eseguibile `WordProcessor`, purché `CFBundleExecutable` corrisponda al file effettivo. Copiare l'icona compilata in `Contents/Resources` e dichiararla in `CFBundleIconFile`.

Il progetto usa attualmente l'estensione `.wpx`, il tipo `local.wordprocessor.document` e il bundle identifier `local.wordprocessor.prototype`. Non modificarli automaticamente: valutare la compatibilità con i documenti esistenti e le impostazioni di macOS. Verificare che i documenti esistenti si aprano dopo il cambiamento. Ricompilare e controllare il nome e l'icona in Finder, Dock e menu dell'applicazione.

Questa cartella prepara il passaggio di consegne; il codice e lo script non sono stati modificati.
