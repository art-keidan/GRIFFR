# Finestra principale e copie compilate

Correzione del 5 novembre 2026.

Il pulsante Lorem inserisce titoli e sezioni dentro la sezione del cursore. Ripetendolo in fondo al testo, il percorso degli oggetti diventa sempre più lungo. La barra trasmetteva la propria larghezza minima alla finestra: la prova ha riprodotto una crescita da 1180 a 1816 punti e l'impossibilità di restringerla.

Il percorso ora occupa una zona a scorrimento orizzontale. I pulsanti conservano aspetto e azioni; anche quelli oltre la larghezza visibile restano raggiungibili. La lunghezza del percorso non impone più le dimensioni della finestra. Alla riapertura, una cornice salvata troppo grande viene riportata entro lo schermo.

L'applicazione corrente è `build/GRIFFR Stili.app` all'interno del fork. Lo script aggiorna quella destinazione. Le compilazioni precedenti restano recuperabili nelle cartelle nascoste di conservazione, con estensione `.retired` anziché `.app`; lo stesso trattamento viene applicato alle vecchie copie lasciate dallo script precedente. Il nome interno del bundle coincide con quello visibile: GRIFFR Stili.

La corsa mirata termina senza errori: 12 prove superate e una saltata perché richiede Garamond Premier Pro. Sono verificati sei inserimenti consecutivi, riduzione della finestra alle dimensioni precedenti, accesso ai pulsanti fuori dalla zona visibile, ripristino di una finestra fuori misura, conservazione dello stato della vista, Lorem, zoom e chiusura. La prova del ridimensionamento non richiede quel font ed è stata eseguita.
