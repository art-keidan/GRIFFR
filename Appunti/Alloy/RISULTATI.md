# Esperimento Alloy · nota marginale della tappa 4

7 novembre 2026. Modello: [nota-marginale.als](nota-marginale.als). Alloy 6.2.0, risolutore Glucose, da riga di comando:

```sh
~/Downloads/Alloy.app/Contents/MacOS/alloy exec -q -f -s glucose -t json -o <cartella> -c <comando> nota-marginale.als
```

## Che cosa si è modellato

Paragrafi con identità, parole in ordine, il contenuto scritto dall'autore per la nota legato a un paragrafo che lo «possiede», e quattro operazioni: scrivere e cancellare una parola, spezzare un paragrafo, unirgli il seguente. La nota si aggancia alla quinta parola del suo paragrafo. Le regole d'identità sono quelle del codice (`DocumentStore.resegment`). Per «unisci» si sono provate due regole: le note restano al paragrafo che scompare (*seguono l'identità*), oppure passano a quello che resta (*si spostano*).

Limiti: al più 3 paragrafi, 6–7 parole, 3–4 passi; parole astratte, niente caratteri, note a piè di pagina o sezioni.

## Risultati

| Controllo | Note che seguono l'identità | Note che si spostano |
|---|---|---|
| Una nota è sempre attaccata a un paragrafo del documento | **controesempio** | nessuno |
| Un paragrafo non ha mai due note | nessuno | **controesempio** |
| Dopo una divisione la nota punta ancora la sua parola | **controesempio** | **controesempio** |
| Togliere un a capo e riscriverlo nello stesso punto rimette la nota | **controesempio** | **controesempio** |
| Le operazioni lasciano il documento ben formato | nessuno | nessuno |

Ogni «nessun controesempio» importante ha una controprova (`run Caso…`) che mostra che il caso si può costruire: non passa solo perché è impossibile.

I controesempi, in parole:

1. **Unire due paragrafi che hanno ciascuno una nota.** Se le note seguono l'identità, quella del secondo resta attaccata a un paragrafo che non c'è più. Se si spostano, il paragrafo che resta ne ha due. Serve una regola esplicita: quale nota tenere, o se un paragrafo può averne più d'una.
2. **Spezzare un paragrafo di cinque parole dopo la terza.** L'identità resta alla prima parte, che ha tre parole: la nota resta sospesa, anche se la sua parola esiste ancora, ora seconda del paragrafo nuovo. Se «quinta parola» è una ricerca relativa, questo è il comportamento voluto; altrimenti la nota va legata alla parola.
3. **Togliere un a capo e riscriverlo nello stesso punto.** Il testo torna identico, ma il secondo paragrafo ha un'identità nuova e la nota non torna alla sua parola. Annulla invece funziona: il deposito rimette le identità di prima (prova `undoRestoresIdentity`).

## Che cosa si è scoperto sul codice, durante l'esperimento

- **Il commento su `ParagraphID` è superato.** Dice che spezzando l'identità la tiene «la parte che contiene più del testo di prima»; il codice (`resegment`) e la prova `splitAndMerge` dicono la parte con il primo carattere, cioè la prima. La prima versione del modello seguiva il commento e dava un controesempio su Annulla che nel programma non c'è.
- **`ParagraphID` non si salva.** Il formato scrive l'`id` di sezioni, tabelle, formule e selezioni, ma non dei paragrafi: riaprendo un documento i paragrafi hanno identità nuove. Una nota legata a `ParagraphID` non sopravvive a Salva e riapri; va salvata con il testo, per esempio come attributo, come già le eccezioni alle regole (`rules-off`).

## Che cosa suggerisce per la tappa 4

Il contenuto della nota non va legato all'identità in memoria del paragrafo ma al testo: un attributo sul primo carattere del paragrafo segue già le stesse regole di `resegment`, si salva con il file e torna con Annulla. Le tre scelte, decise il 7 novembre (dettagli in [OGGETTI-EDITORIALI.md](../OGGETTI-EDITORIALI.md)): unendo, i due testi si fondono ma GRIFFR ricorda dove cominciava il secondo; spezzando, la nota resta al primo paragrafo, sospesa; riscrivendo l'a capo nello stesso punto, le due note si separano di nuovo. Il prossimo passo è mettere questa regola nel modello e controllarla.

## Su Alloy

- Ha trovato in pochi secondi tre casi concreti che vanno decisi prima di scrivere la tappa 4.
- Due errori del modello sono costati tempo: `let` è una sostituzione e non un valore salvato, e il punto lega più forte di `#`. Tutti e due rendevano i controlli falsamente rassicuranti. Regola pratica: ogni «nessun controesempio» ha la sua controprova.
- Confrontare il modello con il codice è servito quanto il modello: ha fatto emergere il commento superato e l'identità non salvata.

# Esperimento 2 · la regola «fondi e ricorda il punto»

7 novembre 2026. Modello: [fondi-e-ricorda.als](fondi-e-ricorda.als).

## Che cosa si è modellato

Il testo come sequenza di parole e di a capo, come nel `DocumentStore`: un paragrafo finisce con il suo a capo, e il testo finisce sempre con un a capo. Il testo che l'autore scrive per la nota di un paragrafo è un «pezzo» con un **segno sul primo carattere del paragrafo**, come le eccezioni `rules-off`. La nota di un paragrafo è l'insieme dei pezzi i cui segni cadono dentro di lui. Così «fondi» e «ricorda il punto» non sono regole in più: unendo, il segno del secondo paragrafo finisce dentro il primo; riscrivendo l'a capo prima di quel carattere, torna al suo paragrafo.

Operazioni: scrivere e cancellare una parola, andare a capo, togliere un a capo, scrivere la nota di un paragrafo. Per un carattere con un segno che viene cancellato si sono provate due regole: il segno si perde con lui, oppure passa al carattere che segue.

Limiti: al più 5 parole, 3 a capo, 2 note, 7 caratteri, 4–5 passi.

## Risultati

| Controllo | Esito |
|---|---|
| Il testo resta ben formato | regge (4 passi) |
| Niente testo di nota perso, se il segno **si perde** con il carattere | **controesempio** |
| Niente testo di nota perso, se il segno **passa** al carattere dopo | regge (4 passi) |
| Unendo, le due note si fondono | regge (5 passi) |
| Riscrivendo l'a capo, le note si separano di nuovo | **controesempio** (un caso limite) |
| Spezzando altrove, la nota resta tutta al primo | **controesempio** (diventa la regola voluta) |

Ogni controllo che regge ha la sua controprova `run Caso…`; le tre ricerche lunghe sono arrivate in fondo (4–5 minuti ciascuna), non si sono fermate per il limite di tempo.

1. **Il segno deve passare al carattere dopo.** Se si perde, basta cancellare l'unica parola di un paragrafo con una nota per perderne il testo. Con la regola «passa» non succede mai, nei limiti provati. È una scelta tecnica obbligata.
2. **Il caso del paragrafo vuoto.** Un paragrafo vuoto con una nota (il suo testo è stato cancellato tutto) porta il segno sul suo a capo. Togliendo quell'a capo il segno passa al primo carattere del paragrafo seguente, che ha già il suo: i due segni stanno sullo stesso carattere, e riscrivendo l'a capo non si sa più quale veniva prima. Rimedio: i segni sullo stesso carattere **ricordano il loro ordine**, e un a capo riscritto prima del carattere separa quelli venuti da prima. **Verificato** (vedi sotto).
3. **Dopo un'unione la nota segue il suo testo.** Spezzando il paragrafo unito prima delle parole che erano del secondo, la parte di nota scritta per il secondo va con quelle parole, nel paragrafo nuovo. Deciso il 7 novembre: è il comportamento voluto (la nota segue le parole da cui veniva).

## Errori del modello trovati strada facendo

Come nel primo esperimento, metà del lavoro è stata correggere il modello, e ogni errore lo rendeva o falsamente rassicurante o falsamente allarmante:

- `insert` su una sequenza già piena **taglia l'ultimo elemento in silenzio** (qui l'a capo finale): inserire deve allungare il testo di uno.
- **L'insieme vuoto «è» una parola**: `Text.toks[i] in Word` è vero anche per una posizione che non esiste. La posizione va richiesta esplicitamente.
- Una controprova scritta sullo stato iniziale non trova niente se le note si scrivono dopo: va avvolta in `eventually`.
- Un controllo troppo largo (una nota di un paragrafo qualsiasi invece di quello che si unisce) dava un falso controesempio.

## Il rimedio dell'ordine dei segni · verificato

Nel modello, un segno spostato da un a capo cancellato ricorda di «venire da prima» del carattere che lo porta; riscrivendo l'a capo davanti a quel carattere torna al paragrafo precedente. Un segno spostato dalla cancellazione di una parola invece resta, come fa già il deposito con un a capo scritto all'inizio di un paragrafo (il testo tiene la sua identità).

| Controllo (regola «passa», ordine dei segni) | Esito |
|---|---|
| Riscrivendo l'a capo, le note si separano di nuovo | regge (5 passi, 27 s) |
| Unendo, le due note si fondono | regge (5 passi, 80 s) |
| Niente testo di nota perso | regge (4 passi, 5½ min) |
| Il testo resta ben formato | regge (4 passi, 5 min) |

Controprove: `CasoParagrafoVuoto` (proprio il caso che prima falliva), `CasoRiscrivere`, `CasoUnire`, `Esempio`. Tutte le ricerche sono arrivate in fondo.

Limite: con due note basta ricordare se un segno «viene da prima»; con tre o più note fuse una dopo l'altra servirà l'ordine completo dei segni su un carattere, da provare con un limite di tre note quando si scrive il codice.
