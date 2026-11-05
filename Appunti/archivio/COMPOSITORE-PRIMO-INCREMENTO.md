# Primo incremento del compositore

4 novembre 2026

L'app compilata si trova in **build/GRIFFR Stili.app**, con identità propria. Il comando **Formato → Compositore di stili…** apre una bacheca in una finestra indipendente, ridimensionabile. Il documento resta utilizzabile. Chiudendo il documento si chiude anche la sua bacheca. Riaprendo la bacheca durante il lavoro si ritrovano le bozze.

Ogni scheda contiene una formula con nome. Le pills espongono i passaggi **Questo paragrafo → Raccogli → Scegli posizione → risultato**. Cliccando su Raccogli si scelgono parole, sigle o numeri. La posizione apre le scelte numeriche e una voce per un argomento personalizzato. **＋ Formula** aggiunge una scheda da completare scegliendo un predicato.

Sotto ciascuna formula si possono collegare più trattamenti. Le pills scelgono lo stile del paragrafo cui applicarsi, lo stile di trattamento e lo stato attivo o sospeso. Le schede mostrano il risultato sul campione modificabile in basso. Colori e bordi delle pills riprendono Theme e i pulsanti di GRIFFR, anche nell'aspetto scuro.

**Applica al documento** registra l'insieme delle bozze in un passo annullabile mantenendo aperta la bacheca. **Ricarica dal documento** sostituisce le bozze con le definizioni correnti. Se gli stili sono cambiati nel documento nel frattempo, l'applicazione richiede prima una ricarica ed evita di sovrascrivere quelle modifiche.

## Come provarlo

Aprire [il documento di esempio](prova-compositore.grx) con GRIFFR Stili. La quinta parola compare rossa nei paragrafi Testo e blu nelle Citazioni. Aprire la bacheca, trovare **Parola del richiamo**, cliccare la pill **Scegli · 5** e scegliere la posizione 3. Premere **Applica al documento**. I due trattamenti seguono la nuova posizione. Aggiungere un'altra formula e scegliere i suoi passaggi dalle pills per costruire una selezione indipendente.

Salvare una copia, riaprirla e cambiare ancora la posizione. L'identità della selezione rimane la stessa anche cambiandone il nome. Se il capoverso contiene meno parole del necessario il trattamento rimane inattivo. Il formato 3 conserva nome, identità, sorgente, posizione e riferimenti delle regole. Il salvataggio con incremento di versione propone una copia e protegge il file originale.

## Stato delle verifiche

Compilazione debug e release riuscite. Le 22 prove mirate su regole, selezione condivisa, provenienza e distanza a inizio pagina passano. La prova della selezione salva e riapre due regole, ne cambia il bersaglio attraverso la definizione condivisa e verifica il risultato composto, l'assenza del bersaglio, le sigle dopo un apostrofo e il rifiuto di riferimenti XML non validi.

La verifica automatica della bacheca controlla che apra una finestra separata, che una seconda apertura riusi la stessa finestra, che le bozze si applichino in un passo annullabile e che un conflitto col documento consenta di ricaricare. La nuova disposizione delle pills resta da valutare visivamente nell'app. Il vocabolario disponibile comprende la selezione di parole, sigle e numeri in una posizione e i trattamenti associati. Le ulteriori operazioni, ramificazioni e testate del catalogo richiedono altri incrementi.

[Proposta delle interfacce](INTERFACCE.md) · [Catalogo](CATALOGO-OPERAZIONI.md)
