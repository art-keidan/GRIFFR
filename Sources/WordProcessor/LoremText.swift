import AppKit
import Typesetting

/// Il brano del pulsante «Lorem»: circa due pagine di prosa italiana, con tre titoletti, per provare la composizione.
/// È italiano corrente, perché la correzione ortografica non lo segni tutto.
enum LoremText {
    static let family = "Garamond Premier Pro"

    /// Un paragrafo d'apertura, poi tre parti con il loro titoletto.
    static let opening = """
        Chi apre un libro raramente pensa alla pagina che ha davanti. Legge, volta il foglio, prosegue; e se la lettura scorre \
        senza intoppi, il merito è in buona parte di scelte che nessuno nota. La larghezza della colonna, la distanza fra le \
        righe, il carattere e il suo corpo, i margini che incorniciano il testo: tutto concorre a rendere la lettura facile o \
        faticosa. Quando queste scelte sono giuste, scompaiono; quando sono sbagliate, il lettore si stanca senza sapere perché.
        """

    static let parts: [(title: String, paragraphs: [String])] = [
        ("La misura della riga", [
            """
            Una riga troppo lunga costringe l’occhio a un viaggio faticoso: arrivato in fondo, deve tornare indietro e cercare \
            l’inizio della riga successiva, e spesso sbaglia, rileggendo la stessa o saltandone una. Una riga troppo corta, al \
            contrario, spezza continuamente il discorso e obbliga a frequenti divisioni in sillabe. La tradizione tipografica \
            suggerisce una misura intermedia, che contenga all’incirca dai sessanta ai settanta caratteri, spazi compresi.
            """,
            """
            Non si tratta di una regola fissa, ma di un punto di partenza. Un romanzo, che si legge a lungo e senza fretta, \
            sopporta righe un po’ più ampie; un giornale, che si scorre rapidamente, preferisce colonne strette. Anche il corpo \
            del carattere conta: a parità di larghezza, un testo più piccolo mette in riga più parole, e la misura che sembrava \
            giusta diventa d’un tratto eccessiva.
            """,
            """
            Lo spazio fra le righe completa il quadro. Se le righe sono troppo vicine, le lettere che scendono sotto la linea di \
            base sfiorano quelle che salgono dalla riga seguente, e la pagina si fa scura e compatta. Se sono troppo lontane, il \
            testo si sfalda in tante strisce separate. Una buona interlinea lascia respirare la pagina senza disperderla.
            """,
            """
            Infine, c’è la questione dell’allineamento. Il testo giustificato, con le righe che terminano tutte allo stesso punto, \
            dà alla pagina un aspetto ordinato e solenne, ma richiede una buona divisione in sillabe: senza di essa, le parole si \
            allargano e si stringono, e fra l’una e l’altra si aprono vuoti che attraversano la pagina come fiumi bianchi.
            """,
            """
            Il testo allineato a sinistra, con il margine destro libero e irregolare, evita questi vuoti e mantiene costante la \
            distanza fra le parole. È una scelta più modesta, ma spesso più leggibile, soprattutto nelle colonne strette e nei \
            testi che si leggono in fretta.
            """,
        ]),
        ("Il carattere e la sua voce", [
            """
            Ogni carattere ha una sua voce. Alcuni sono sobri e discreti, adatti a un saggio o a un manuale; altri hanno un tono \
            più solenne, e stanno bene in un frontespizio o in un’epigrafe. I caratteri nati nelle tipografie veneziane del \
            Cinquecento, con le loro grazie sottili e il contrasto moderato fra tratti pieni e tratti filiformi, restano ancora \
            oggi tra i più riposanti per la lettura prolungata.
            """,
            """
            Il corsivo, nato in quegli stessi anni come carattere autonomo, ha finito per diventare un compagno del tondo: serve a \
            mettere in evidenza una parola, un titolo, un termine straniero, senza alzare la voce. Il neretto, invece, si fa \
            notare subito, e per questo va usato con parsimonia; in un testo continuo è quasi sempre fuori posto, mentre nei \
            titoli e nelle didascalie può aiutare a orientarsi.
            """,
            """
            Anche i dettagli minuti hanno il loro peso. Le virgolette basse, gli apostrofi curvi, la lineetta distinta dal \
            trattino, il maiuscoletto per le sigle: sono piccole attenzioni che il lettore non registra consapevolmente, ma che \
            nell’insieme danno alla pagina un aspetto curato e coerente.
            """,
            """
            Scegliere un carattere significa anche conoscerne le famiglie. Una famiglia ben progettata offre non soltanto il tondo \
            e il corsivo, ma diversi pesi, il maiuscoletto, le cifre di stile antico che scendono e salgono come le lettere \
            minuscole, e magari versioni pensate per i corpi piccoli e per quelli grandi. Con questi strumenti si può comporre un \
            libro intero senza mai uscire dalla stessa famiglia.
            """,
            """
            Mescolare caratteri diversi è possibile, ma richiede misura. Due caratteri troppo simili sembrano un errore; due \
            caratteri troppo diversi litigano fra loro. Di solito conviene affidare il testo a un carattere solo e, se proprio si \
            vuole un contrasto, riservare il secondo ai titoli.
            """,
        ]),
        ("La pagina come spazio", [
            """
            I margini non sono spazio sprecato. Danno alla colonna di testo un luogo dove posarsi, lasciano alle dita lo spazio \
            per reggere il libro senza coprire le parole, e accolgono, quando serve, le note e i richiami. Nei libri antichi il \
            margine esterno e quello inferiore erano più ampi degli altri, così che le due pagine affiancate formassero un \
            blocco unico, raccolto verso il centro.
            """,
            """
            Anche la successione delle pagine ha le sue regole. Un capitolo comincia di solito su una pagina nuova, spesso a \
            destra; un titolo non dovrebbe mai restare solo in fondo a una pagina, staccato dal testo che introduce; e una riga \
            isolata, rimasta sola in cima o in fondo alla colonna, disturba l’occhio come una nota stonata. Evitare questi \
            inconvenienti richiede pazienza, e a volte qualche piccolo ritocco al testo stesso.
            """,
            """
            Le note a piè di pagina pongono problemi simili. Devono stare sulla stessa pagina del richiamo, ma non possono \
            crescere tanto da soffocare il testo principale; quando sono lunghe, si spezzano e proseguono nella pagina seguente. \
            Un buon programma di composizione se ne occupa da sé, ma è utile sapere che cosa sta facendo.
            """,
            """
            Le immagini, infine, chiedono a loro volta un posto. Una figura dovrebbe comparire vicino al punto in cui il testo la \
            nomina, senza interrompere una frase a metà; quando questo non è possibile, la si sposta in cima o in fondo alla \
            pagina, e una didascalia breve ricorda al lettore di che cosa si tratta.
            """,
            """
            Alla fine, il compito di chi compone una pagina è servire il testo. Il lettore non deve accorgersi del lavoro che sta \
            dietro, ma soltanto trovare le parole al loro posto, chiare e tranquille, pronte a essere lette. È un lavoro fatto \
            di misure e di proporzioni, ma anche di ascolto: bisogna capire che cosa il testo chiede, e dargli la forma che gli \
            permette di parlare.
            """,
        ]),
    ]

    /// Il brano come documento con gli stili di `settings`: il corpo nello stile «Testo», i titoletti nello stile del
    /// primo livello (aggiunto, se il foglio non ne ha); tutto in Garamond Premier Pro, se c'è, con il nero dove lo stile
    /// lo vuole. I titoletti nascono al primo livello con lo stile di quel livello: incollati dentro una sezione scendono,
    /// e lo stile li segue.
    static func document(settings: Document, resolver: FontRoleResolver) -> Document {
        var sheet = settings.styles
        let bodyStyle = sheet.style(named: "Testo") != nil ? "Testo" : nil
        var titleStyle = sheet.headingStyles(forLevel: 1).first
        if titleStyle == nil, let (newSheet, name) = sheet.headingStyle(forLevel: 1, replacing: nil) {
            sheet = newSheet
            titleStyle = name
        }
        func run(_ text: String, style: String?) -> Paragraph {
            var character = sheet.resolveCharacter(paragraphStyle: style, wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            let traits = TextStyling.traits(ofFace: character.fontName)
            let role = resolver.role(of: character) ?? FontRole(italic: traits?.italic ?? false, bold: traits?.bold ?? false)
            if let face = resolver.resolve(family: family, role: role) {
                character.fontName = face.fontName
                character.variations = face.variations
                character.prefersVariableFont = face.prefersVariableFont
                character.features = []
                character.fontRole = role
            }
            return Paragraph(styleName: style, style: sheet.resolveParagraph(styleName: style), inlines: [.text(TextRun(text, style: character))])
        }
        var result = settings.settingsOnly
        result.styles = sheet
        result.blocks = [.paragraph(run(opening, style: bodyStyle))]
        if let titleStyle {
            let role = sheet.values(of: titleStyle).opensSection ?? Section.Role.section
            result.sections = parts.map { part in
                Section(role: role, title: run(part.title, style: titleStyle), blocks: part.paragraphs.map { .paragraph(run($0, style: bodyStyle)) })
            }
        } else {
            result.blocks += parts.flatMap { [run($0.title, style: bodyStyle)] + $0.paragraphs.map { run($0, style: bodyStyle) } }.map { .paragraph($0) }
        }
        return result
    }
}
