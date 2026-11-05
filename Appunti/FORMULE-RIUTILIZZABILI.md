# Formule riutilizzabili

La bacheca permette di creare definizioni nominate con parametri, risultato dichiarato e chiamate ad altre definizioni. Il primo vocabolario comprende numeri, lunghezze in punti, booleani, costanti, parametri e somme. Le espressioni possono contenere più passaggi; lo stesso risultato può alimentare più proprietà e stili.

## Percorso completo

1. Aprire `prova-formule-riutilizzabili.grx` nell'app aggiornata.
2. Scegliere **Formato → Compositore di stili → Formule**. La definizione «Rientro con margine» riceve Base e aggiunge 6 pt. Gli argomenti di prova permettono di controllare il risultato prima di applicare.
3. Modificare la costante 6 in 10. In **Stili → Citazione calcolata** il rientro richiama la definizione con Base 12 pt: il risultato diventa 22 pt. **Applica al documento** aggiorna entrambi i paragrafi.
4. Annulla e Ripeti ripristinano definizione e resa. Salvare e riaprire conserva identità, chiamata e argomenti.
5. Per costruire una definizione, aggiungere una Formula, scegliere il tipo di risultato e usare il menu dell'espressione: costante, parametro, somma o richiamo a una definizione compatibile. Ogni richiamo espone gli argomenti della firma.
6. Nella riga di una proprietà compatibile dello stile, attivare **Calcola con una formula** e scegliere il richiamo. Disattivandolo, il risultato corrente diventa un valore fisso.

I nomi sono etichette modificabili; i collegamenti usano identificatori stabili. Il programma segnala parametri o riferimenti mancanti, tipi incompatibili, cicli e limiti di espansione. Una definizione ancora usata non può essere rimossa dalla bacheca. Quando cambia una firma, i punti di chiamata permettono di aggiornare gli argomenti esplicitamente.

Le proprietà che ricevono misure, interi o booleani possono leggere questi risultati. Le altre mantengono i propri controlli. L'ispettore mostra il richiamo e richiede una scelta esplicita prima di sostituirlo con un valore fisso.

Il formato 11 aggiunge i collegamenti delle proprietà alle definizioni conservate dal formato 10. I documenti precedenti continuano a usare la propria versione minima. Incollando testo, vengono importate le dipendenze degli stili usati; le identità e i nomi in conflitto vengono separati e i richiami aggiornati secondo la politica di importazione degli stili.

Questa consegna completa il percorso per il vocabolario descritto. Operazioni su oggetti editoriali, risultati facoltativi, campi generali e testate appartengono alle estensioni del catalogo.
