import AppKit
import Typesetting

/// Il brano del pulsante «Lorem»: circa due pagine di prosa inglese, con tre titoletti, per provare la composizione.
/// È inglese corrente, con la lingua inglese data al testo, perché la correzione ortografica non lo segni tutto.
enum LoremText {
    static let family = "Garamond Premier Pro"
    /// La lingua del brano.
    static let language = "en"

    /// Un paragrafo d'apertura, poi tre parti con il loro titoletto.
    static let opening = """
        Whoever opens a book seldom thinks about the page in front of them. They read, turn the leaf, and go on; and if the \
        reading flows without a hitch, much of the credit goes to choices nobody notices. The width of the column, the \
        distance between the lines, the typeface and its size, the margins that frame the text: everything helps to make \
        reading easy or tiring. When these choices are right, they disappear; when they are wrong, the reader grows tired \
        without knowing why.
        """

    static let parts: [(title: String, paragraphs: [String])] = [
        ("The measure of the line", [
            """
            A line that is too long forces the eye into a tiring journey: once it reaches the end, it has to travel back and \
            find the start of the next line, and it easily loses its way. A line that is too short breaks the sentence into \
            small pieces, and the reader jumps from one line to the next without ever settling into the rhythm of the text. \
            Between the two lies a comfortable measure, which experience puts at around sixty or seventy characters.
            """,
            """
            The distance between the lines matters as much as their length. A long line needs more air, so that the eye can find \
            its way back; a short line can stay closer. A type with tall lowercase letters looks bigger than its size suggests, \
            and asks for a little more space. These are not rigid rules but habits of the eye, which the compositor learns to \
            respect.
            """,
            """
            Justified text gives the page a calm, even look, but it has a price: the spaces between the words grow and shrink \
            from line to line. Hyphenation helps to keep them even, and a good line-breaking program weighs the whole paragraph \
            instead of one line at a time, so that no line is left too loose or too tight.
            """,
            """
            Readers rarely measure anything, yet they feel at once when a page has been set with care. A column that is too \
            wide for its type, or lines packed too tightly, make the text look dark and heavy before a single word has been \
            read. A well balanced page, instead, invites the eye to begin, and keeps it company until the last line.
            """,
        ]),
        ("The typeface and its voice", [
            """
            Every typeface has a voice. Some speak softly and step aside, leaving room for the words; others draw attention to \
            themselves and give the text a strong character. For long reading the first kind is almost always better: the reader \
            should hear the author, not the type.
            """,
            """
            Italic was born as a typeface of its own, and only later became the companion of the roman. Today it marks emphasis, \
            titles of works and foreign words, and it does so best when it is used sparingly. Bold, on the other hand, is a loud \
            voice: it is useful in headings and in reference works, but in running text it breaks the grey of the page.
            """,
            """
            Small capitals, old-style figures and ligatures are the details that distinguish a careful page from an ordinary \
            one. A good font provides them, and a good program lets the author use them without effort, so that abbreviations do \
            not shout and numbers sit quietly among the letters.
            """,
            """
            Choosing a typeface also means choosing its family. A text needs a roman, an italic and often small capitals that \
            belong together, drawn with the same hand and the same rhythm. When the italic comes from another family, the page \
            loses its unity, and even a reader who knows nothing about type senses that something is out of tune.
            """,
        ]),
        ("The page as space", [
            """
            Margins are not wasted space. They give the column of text a place to rest, they leave room for the fingers that \
            hold the book without covering the words, and they welcome, when needed, notes and references. In classic books the \
            inner margin is narrower than the outer one, so that the two facing pages read as a single field.
            """,
            """
            The succession of pages has its rules too. A chapter usually begins on a new page, often lower down, with its title \
            and a little silence before the text. Notes stay with the line that calls them, figures go as close as possible to \
            the paragraph that mentions them, and a heading never remains alone at the foot of a page.
            """,
            """
            In the end, the task of whoever composes a page is to serve the text. The reader should not notice the work behind \
            it, but only find the words in their place, clear and quiet, ready to be read. It is a craft made of measures and \
            proportions, but also of listening: one has to understand what the text asks for, and give it the form that lets it \
            speak.
            """,
            """
            White space works in the same way between the parts of a book. A little more room before a heading tells the reader \
            that a new subject begins; a little less after it binds the heading to its text. Each of these distances is small, \
            but together they give the book its pace, like the pauses in a piece of music.
            """,
        ]),
    ]

    /// Il brano come documento con gli stili di `settings`: il corpo nello stile di base («Body»), i titoletti nello stile del
    /// primo livello (aggiunto, se il foglio non ne ha); tutto in Garamond Premier Pro, se c'è, con il nero dove lo stile
    /// lo vuole. I titoletti nascono al primo livello con lo stile di quel livello: incollati dentro una sezione scendono,
    /// e lo stile li segue.
    static func document(settings: Document, resolver: FontRoleResolver) -> Document {
        var sheet = settings.styles
        let bodyStyle = sheet.bodyStyleName
        var titleStyle = sheet.headingStyles(forLevel: 1).first
        if titleStyle == nil, let (newSheet, name) = sheet.headingStyle(forLevel: 1, replacing: nil) {
            sheet = newSheet
            titleStyle = name
        }
        func run(_ text: String, style: String?) -> Paragraph {
            var character = sheet.resolveCharacter(paragraphStyle: style, wordStyle: nil, characterStyle: nil, base: TextStyling.styleBase)
            character.language = language
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
