# GRIFFR · Progetto delle interfacce

Tappa 6 · Proposta del 4 novembre 2026

Il [prototipo navigabile](prototipo-interfacce.html) illustra le tre modalità e i quattro casi guida. I testi, le misure e i risultati visualizzati sono esempi. Il prototipo serve a valutare l'interazione, mentre la composizione effettiva resta da realizzare nel motore.

## Le tre modalità

| | Essenziale | Dettagliata | Compositore |
|---|---|---|---|
| Attività | Scrivere, scegliere e applicare uno stile, regolare font e misure comuni | Definire proprietà, tenuta, condizioni frequenti e provenienza | Comporre operazioni, relazioni, effetti e testate |
| Accesso | Apertura normale del documento | Comando esistente «Interfaccia dettagliata» | «Apri compositore» dalla scheda dello stile o da una spiegazione nell'ispettore |
| Vista | Pagina e comandi comuni | Pagina, mappa, ispettore e definizioni | Stile a sinistra, regola al centro, anteprima e diagnosi a destra |
| Dati | Selezione, documento e stili condivisi | Gli stessi, con controlli ulteriori | Una bozza della stessa definizione, applicata solo alla conferma |

Una regola complessa continua a funzionare in tutte le modalità. In essenziale l'utente vede lo stile e il risultato. In dettagliata trova un riepilogo leggibile, anche quando non c'è un controllo dedicato. Il compositore mostra la definizione completa. I controlli semplici aggiornano soltanto la proprietà dichiarata, conservando le altre parti dello stile.

## Percorso 1 · Distanza d'apertura

1. Nella modalità dettagliata si apre lo stile «Titolo di capitolo» e si seleziona «Posizione e spazi».
2. Si abilita «Quando apre una pagina» e si imposta «Distanza dal margine superiore dello specchio» a 30 mm. Il controllo indica che la distanza riguarda l'intero blocco di apertura.
3. L'anteprima mostra un titolo nel flusso e uno a inizio pagina. Un esempio di titolo portato a pagina nuova da «tieni col seguente» verifica la variante.
4. «Apri nel compositore» mostra la condizione, la proprietà e il valore della stessa regola. Annullare la modifica ripristina la definizione precedente.

Se una definizione contiene una condizione che il controllo dedicato non rappresenta, il riepilogo mostra «Regola personalizzata» e offre l'apertura nel compositore. Il controllo non deve sovrascriverla silenziosamente.

## Percorso 2 · Invio e capoverso successivo

La sezione «Scrittura» dello stile contiene «Dopo Invio in fondo al paragrafo: Corpo». Un'altra sezione, «Influenza sui vicini», mostra «Primo blocco successivo della sezione, se è un capoverso: rientro prima riga 0 mm». L'indicatore «Obbligatorio» è esplicito e indica l'effetto sui valori manuali.

Nell'ispettore del capoverso successivo si legge «Rientro 0 mm · imposto da Titolo di capitolo». Espandendo il dettaglio si vede «Valore dato qui: 8 mm · sospeso». Sono disponibili «Vai allo stile» e «Mostra la regola». Per impostazione proposta il valore sospeso si può modificare, ma non diventa effettivo finché permane il vincolo.

## Percorso 3 · Testata di capitolo

Da uno stile di titolo si apre «Testata». Un elenco ordinato contiene Numero, Spazio, Filetto, Spazio e Titolo. Il pannello di destra regola font, allineamento e misura dell'elemento selezionato. Un'anteprima accosta pagina dispari e pari e offre titoli brevi e lunghi. Il numero della sezione viene usato una sola volta. La quota d'apertura riguarda il bordo della testata, con un controllo esplicito per scegliere una parte diversa.

L'utente può riordinare le parti con tastiera o pulsanti oltre che con trascinamento. Il progetto iniziale comprende sequenze verticali e allineamenti. Le composizioni sovrapposte restano oggetto di una successiva estensione.

## Percorso 4 · Quinta parola e nota marginale

Nel compositore si parte da «Questo paragrafo», si aggiungono «Parole» e «Scegli posizione 5». L'uscita è una parola facoltativa. Il ramo «Quando presente» conduce all'effetto «Presenta nota marginale». Le impostazioni mostrano «Bordo esterno del foglio: 10 mm», «Allinea alla riga dell'ultimo carattere della parola» e «Stile del contenuto: X».

L'anteprima rende evidente il lato della pagina e mostra la parola trovata. Con un testo di quattro parole compare «Quinta parola non trovata · nota sospesa». Un comando «Apri contenuto della nota» resta disponibile anche in questo stato. Il testo inserito dall'autore viene conservato e torna visibile quando ricompare il bersaglio.

## Proposta per il compositore

Propongo una disposizione per righe collegate, espandibili in rami, con i valori e il tipo in uscita mostrati accanto a ogni operazione. Il trascinamento è opzionale. Ogni collegamento si può creare scegliendo da un menu filtrato per tipo e modificare da tastiera. Il pannello «Operazioni disponibili» cerca per termini tipografici, ad esempio «quinta parola» e «bordo pagina», oltre che per nome tecnico.

L'anteprima usa una copia del documento o un campione locale. Il pulsante «Applica» salva la definizione in un'unica operazione annullabile. «Annulla» scarta la bozza. Aprendo una definizione valida non si modifica nulla fino all'applicazione. Se la definizione originale cambia mentre la bozza è aperta, il compositore presenta il conflitto prima di applicare.

I parametri hanno etichette e unità. Un collegamento incompatibile indica sia il tipo richiesto sia quello ricevuto. Una parola mancante produce uno stato sospeso, non un errore. Una dipendenza circolare blocca l'applicazione e mostra la catena coinvolta. Un vincolo non soddisfatto espone valore richiesto e valore effettivo.

## Accessibilità e riscontro

Tutti i passaggi devono essere raggiungibili da tastiera, con ordine di lettura e nomi per VoiceOver. I collegamenti visuali hanno una descrizione testuale. L'anteprima comunica lo stato anche senza colore. Le dimensioni e il contrasto vanno verificati nell'app reale, insieme alla compatibilità con le preferenze di macOS.

L'interfaccia proposta parte dai pannelli e dalle due modalità già presenti. Non costituisce una verifica di usabilità dell'app: servono prove con il motore e con l'utente. Prima dell'implementazione delle interfacce, la tappa 7 deve definire come salvare e migrare le nuove definizioni senza perdere le regole dei documenti esistenti.
