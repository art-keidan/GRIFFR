# Predicato Sottrai

Sottrai affianca Imposta e Aggiungi nelle formule e nel menu della prima pill. È disponibile per ruolo del font, corpo, spazi e rientri. Le proprietà discrete, come famiglia e allineamento, continuano a offrire Imposta.

| Formula | Ingresso | Risultato |
|---|---|---|
| Sottrai · Font · Grassetto | Grassetto corsivo | Corsivo |
| Sottrai · Font · Corsivo | Grassetto corsivo | Grassetto |
| Sottrai · Font · Grassetto corsivo | Grassetto corsivo | Tondo |
| Sottrai · Spazio prima · 6 pt | 12 pt | 6 pt |
| Sottrai · Rientro sinistro · 6 pt | 24 pt | 18 pt |
| Sottrai · Corpo · 2 pt | 12 pt | 10 pt |

Un tratto assente lascia invariato il font. Tondo non contiene tratti da rimuovere, quindi Sottrai Font Tondo lascia invariato il font. Per ottenere sempre il tondo si usa Imposta Font Tondo. Togliere soltanto il corsivo conserva il peso delle facce libere attraverso la stessa politica del risolutore già usata per aggiungerlo.

Le misure conservano le unità e i vincoli esistenti: il corpo deve restare maggiore di zero, gli spazi non negativi; i rientri possono diventare negativi. Un risultato invalido viene segnalato e impedisce di applicare la bozza. Un argomento negativo segue l'aritmetica ordinaria: sottrarre −6 pt equivale ad aggiungere 6 pt.

Ogni ricomposizione rilegge l'ingresso: la sottrazione non si accumula fra ricomposizioni successive. L'ordine delle formule resta significativo.

## Salvataggio e compatibilità

Il file conserva il predicato `subtract`. Un documento che lo usa richiede il formato 6; i documenti senza Sottrai conservano il formato richiesto dalle altre funzionalità. Il lettore rifiuta Sottrai dichiarato in un formato precedente. La protezione dell'originale durante l'aggiornamento resta attiva.

Le dichiarazioni storiche dei tratti esplicitamente disattivati restano per ora nel percorso di compatibilità. La loro conversione automatica richiede anche la verifica delle precedenze dell'eredità; questo incremento rende disponibile Sottrai per le formule create e modificate nella bacheca.

## Prove

Le verifiche coprono le sedici combinazioni fra ruolo iniziale e ruolo da sottrarre, misure e unità, rivalutazione, limiti, eredità, identità delle formule, salvataggio v6 e rifiuto delle versioni precedenti. La prova dell'editor passa fra tutti e tre i predicati sullo stile Forte e controlla il font effettivo, Annulla, Ripeti e riapertura.

Le 19 prove mirate sono passate: 7 dell’editor e 12 del motore.

[Documento di prova](prova-sottrai.grx): aprirlo nell’app aggiornata e scegliere gli stili nella bacheca per modificare i tre esempi.

## Correzione dell'assegnazione al testo

Il primo controllo verificava la valutazione delle formule e il cambio di definizione, ma non l'assegnazione di Senza grassetto a testo già reso grassetto a mano. Quel caso è stato riprodotto: la vecchia assegnazione preservava il grassetto come eccezione locale e non applicava il predicato al suo ingresso reale.

Quando si assegna uno stile, le sue formule esplicite sul font ora leggono il font di ciascun tratto destinatario. Sottrai Font Grassetto rimuove anche il grassetto manuale, mantenendo il corsivo e le proprietà estranee al font. Imposta e Aggiungi seguono lo stesso percorso. Le formule ereditate del font sono incluse, l'ordine è conservato e una nuova assegnazione di Sottrai Font Grassetto lascia il risultato stabile.

Le prove dell'editor coprono la selezione parziale, tutti e tre i tipi di stile, gli attributi di scrittura al cursore, Annulla/Ripeti e salvataggio con riapertura. Questa correzione riguarda l'assegnazione dei predicati del font; le proprietà storiche senza formule mantengono la precedenza precedente.

La verifica completa dopo la correzione supera tutte le 193 prove dell’editor. Le 468 prove del motore riportano le stesse 20 segnalazioni preesistenti, senza nuove segnalazioni. Il pacchetto dell’app è stato ricompilato e verificato.
