# Piano di riprogettazione di GRIFFR

4 novembre 2026

Questo percorso usa Astra per le decisioni architetturali più difficili, mentre Sol e Terra aiutano a prepararle, realizzarle e verificarle. I modelli sono indicazioni pratiche, non garanzie: il passaggio da una tappa alla successiva dipende dal risultato ottenuto.

| Tappa | Lavoro | Modello consigliato | Risultato |
|---|---|---|---|
| **1. Precisare la visione** | Raccogliere gli esempi: proprietà contestuali, comportamenti alla pressione di Invio, effetti su altri elementi, testate di capitolo, flottanti. Chiarire che cosa deve aggiornarsi automaticamente e che cosa invece è un'azione dell'editor. | **Terra o Sol** | Un documento breve, scritto in termini tipografici, con obiettivi e casi d'uso. |
| **2. Fotografare GRIFFR oggi** | Esaminare in dettaglio modello del documento, deposito vivo, stili, regole, compositore, interfaccia e formato `.wpx`. Distinguere ciò che esiste già da ciò che manca. | **Sol** | Una mappa dell'architettura attuale e dei suoi vincoli, con riferimenti al codice. |
| **3. Disegnare il modello nuovo** | Definire oggetti, identità, proprietà, relazioni, operazioni componibili, stili ed effetti. Stabilire come si consultano contenuto e geometria, come si risolvono i conflitti e come si evitano dipendenze circolari. | **Astra** | Un progetto architetturale motivato, con alternative e decisioni ancora aperte. |
| **4. Mettere alla prova il disegno** | Esprimere nel nuovo modello gli esempi: primo paragrafo della pagina, titolo e paragrafo seguente, testate `memoir`, quinta parola e flottante. Verificare anche modifica del testo, paginazione e salvataggio. | **Astra** | Scenari dettagliati che mostrino dove il modello funziona e dove deve essere corretto. |
| **5. Definire il vocabolario iniziale** | Scegliere un numero limitato di operazioni primitive, i loro parametri e risultati; progettare come comporle, dare un nome alle combinazioni e riutilizzarle. Stabilire anche che cosa resta fuori dalla prima versione. | **Astra**, poi **Sol** per dettagliare | Un primo catalogo coerente, con esempi di espressioni visuali. |
| **6. Progettare le tre interfacce** | Stabilire che cosa si vede nell'interfaccia essenziale, in quella avanzata e nel compositore visuale. Progettare come l'ispettore spiega l'origine di una formattazione. | **Sol**; **Terra** per prove visive e revisione delle schermate | Flussi e prototipi delle interfacce, basati sullo stesso modello. |
| **7. Preparare la migrazione** | Suddividere il cambiamento in passi compatibili con il codice esistente; definire evoluzione del formato `.wpx`, conservazione dei documenti e prove di regressione. | **Astra** per il piano; **Sol** per dettagli e realizzazione | Una sequenza di interventi verificabili, con rischi e criteri di completamento. |
| **8. Costruire una prima funzione completa** | Implementare un percorso dall'interfaccia al salvataggio e alla composizione. Un candidato è la proprietà condizionata «quando il paragrafo inizia una pagina», verificando che copra anche il titolo di capitolo. | **Sol**, con revisione **Astra** se emergono scelte fondamentali | Una prima funzione utilizzabile che collauda il nuovo impianto. |
| **9. Estendere gradualmente** | Aggiungere operazioni, comportamenti e composizioni di testata seguendo i casi d'uso prioritari, con prove e documenti di esempio. | **Sol** per sviluppo; **Terra** per interventi circoscritti e verifiche visive; **Astra** per revisioni periodiche | Un sistema che cresce senza dover anticipare tutto. |

La [documentazione OpenAI](https://developers.openai.com/api/docs/guides/model-selection) colloca Astra sui problemi ambigui e sulle analisi profonde, Sol sui progetti complessi con attenzione a tempi e costi, e Terra sui compiti più circoscritti e visivi: è il criterio applicato qui.

Non partire da una riscrittura generale. Il primo traguardo è arrivare alla fine della tappa 4 con un progetto che l'ideatore riconosca come proprio e che sappia spiegare come realizzare alcuni esempi reali. Solo allora decidere quanto del codice attuale cambiare.

Per conservare le decisioni fra una sessione e l'altra, salvare nel progetto i risultati: visione, esempi, architettura, catalogo delle operazioni e piano di migrazione. Così il passaggio fra modelli non dipenderà soltanto dalla memoria della conversazione.
