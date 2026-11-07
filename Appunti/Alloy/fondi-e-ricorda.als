-- GRIFFR · esperimento Alloy 2: la regola «fondi e ricorda il punto» per le note prodotte da uno stile.
--
-- Decisioni del 7 novembre (Appunti/OGGETTI-EDITORIALI.md):
--   · unendo due paragrafi con una nota ciascuno, i testi si fondono in una nota sola, e GRIFFR ricorda dove
--     cominciava il secondo;
--   · spezzando il paragrafo, la nota resta al primo;
--   · togliendo un a capo e riscrivendolo nello stesso punto, le due note si separano di nuovo.
--
-- Come lo si realizzerebbe: il testo dell'autore di ogni nota è un «pezzo» con un segno sul carattere dove
-- cominciava il suo paragrafo (come le eccezioni rules-off, un attributo del testo). La nota di un paragrafo è
-- l'insieme dei pezzi i cui segni cadono dentro di lui. Così fondere e ricordare il punto vengono da soli.
--
-- Il testo è una sequenza di parole e di a capo, come nel DocumentStore: un paragrafo finisce con il suo a capo,
-- e il testo finisce sempre con un a capo (il paragrafo finale). Si provano due regole per un carattere che porta
-- un segno e viene cancellato: il segno si perde con lui (`Lose`), o passa al carattere che segue (`Pass`).
--
-- Attenzione: `let` è una sostituzione, non un valore salvato; i valori da confrontare fra due stati si fissano
-- con un quantificatore. Ogni «nessun controesempio» ha una controprova `run`.
--
-- Limiti: al più 5 parole, 3 a capo, 2 pezzi di nota, 7 caratteri, 4 passi; niente quinta parola (la sospensione
-- non tocca dove sta il testo della nota), niente taglia e incolla.

module fondiERicorda

abstract sig Tok {}
sig Word, Nl extends Tok {}

one sig Text { var toks: seq Tok }

-- Un pezzo di testo di nota scritto dall'autore, con il carattere che porta il suo segno.
sig Piece { var home: lone Tok }
-- I pezzi già scritti, e gli a capo già usati (un carattere cancellato non torna).
var sig Made in Piece {}
var sig Spent in Tok {}
-- I pezzi il cui segno è arrivato da un a capo cancellato: «vengono da prima» del carattere che li porta. Riscrivendo
-- l'a capo davanti a quel carattere tornano al paragrafo precedente. (Nei limiti provati, con due pezzi, basta
-- ricordare questo; con più livelli servirebbe l'ordine completo dei segni su un carattere.)
var sig FromBreak in Piece {}

abstract sig Rule {}
one sig Lose, Pass extends Rule {}
one sig Choice { onDelete: one Rule }

fun live: set Tok { Text.toks.elems }
fun ix[t: Tok]: Int { Text.toks.idxOf[t] }

-- Due caratteri stanno nello stesso paragrafo se fra loro non c'è un a capo (quello del primo dei due escluso).
pred same[a, b: Tok] {
  a + b in live
  let lo = (ix[a] < ix[b] => ix[a] else ix[b]), hi = (ix[a] < ix[b] => ix[b] else ix[a]) |
    no n: Nl & live | ix[n] >= lo and ix[n] < hi
}
fun para[t: Tok]: set Tok { { u: live | same[t, u] } }
fun startOf[t: Tok]: Tok { { s: para[t] | all u: para[t] | ix[s] <= ix[u] } }
-- La nota del paragrafo di `t`: i pezzi con il segno dentro di lui.
fun note[t: Tok]: set Piece { home.(para[t]) & Made }

pred wellFormed {
  some Text.toks
  Text.toks.last in Nl
  not Text.toks.hasDups
  live in Spent
}

pred init {
  wellFormed
  Spent = live
  no Made
  no home
  no FromBreak
}

pred unchangedNotes { home' = home and Made' = Made and FromBreak' = FromBreak }

-- Scrive una parola nuova prima del carattere `i`.
pred typeWord[i: Int, w: Word] {
  w not in Spent
  i >= 0 and i <= Text.toks.lastIdx
  Text.toks' = Text.toks.insert[i, w]
  -- Inserire allunga il testo di uno (oltre il limite di prova, insert taglierebbe l'ultimo carattere).
  #Text.toks' = (#Text.toks).add[1]
  Spent' = Spent + w
  unchangedNotes
}

-- Cancella la parola `i`. Il suo segno, se ne ha, si perde o passa al carattere che segue.
pred deleteWord[i: Int] {
  -- La posizione deve esistere: in Alloy anche l'insieme vuoto «è» una parola.
  i in Text.toks.inds
  Text.toks[i] in Word
  Text.toks' = Text.toks.delete[i]
  Spent' = Spent
  Made' = Made
  all t: Tok | t = Text.toks[i] implies {
    Choice.onDelete = Lose implies (home' = home - (Piece -> t) and FromBreak' = FromBreak - home.t)
    Choice.onDelete = Pass implies (home' = home - (Piece -> t) + (home.t -> Text.toks[i.add[1]]) and FromBreak' = FromBreak)
  }
}

-- Va a capo prima del carattere `i`: il paragrafo si spezza lì.
pred split[i: Int, n: Nl] {
  n not in Spent
  i >= 0 and i <= Text.toks.lastIdx
  Text.toks' = Text.toks.insert[i, n]
  -- Inserire allunga il testo di uno (oltre il limite di prova, insert taglierebbe l'ultimo carattere).
  #Text.toks' = (#Text.toks).add[1]
  Spent' = Spent + n
  Made' = Made
  -- I pezzi venuti da un a capo cancellato davanti a questo carattere tornano all'a capo riscritto.
  all t: Tok | t = Text.toks[i] implies {
    home' = home - ((FromBreak & home.t) -> t) + ((FromBreak & home.t) -> n)
    FromBreak' = FromBreak - home.t
  }
}

-- Toglie l'a capo `i` (non quello finale): il paragrafo si unisce al seguente.
pred merge[i: Int] {
  i in Text.toks.inds
  Text.toks[i] in Nl
  i < Text.toks.lastIdx
  Text.toks' = Text.toks.delete[i]
  Spent' = Spent
  Made' = Made
  all t: Tok | t = Text.toks[i] implies {
    Choice.onDelete = Lose implies (home' = home - (Piece -> t) and FromBreak' = FromBreak - home.t)
    Choice.onDelete = Pass implies (home' = home - (Piece -> t) + (home.t -> Text.toks[i.add[1]]) and FromBreak' = FromBreak + home.t)
  }
}

-- L'autore scrive la nota di un paragrafo che non ne ha: il segno va sul suo primo carattere.
pred writeNote[t: Tok, p: Piece] {
  t in live
  p not in Made
  no note[t]
  home' = home + p -> startOf[t]
  Made' = Made + p
  FromBreak' = FromBreak
  Text.toks' = Text.toks
  Spent' = Spent
}

pred stutter { Text.toks' = Text.toks and Spent' = Spent and unchangedNotes }

fact traces {
  init
  always (stutter
          or (some i: Int, w: Word | typeWord[i, w])
          or (some i: Int | deleteWord[i])
          or (some i: Int, n: Nl | split[i, n])
          or (some i: Int | merge[i])
          or (some t: Tok, p: Piece | writeNote[t, p]))
}

-- 0. Il modello non è vuoto: due note scritte, i paragrafi uniti e di nuovo spezzati.
run Esempio {
  eventually (#Made = 2 and eventually (some i: Int | merge[i] and after (some n: Nl | split[i, n])))
} for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..6 steps

-- 1. Le operazioni lasciano il testo ben formato.
assert BuonaForma { always wellFormed }
check BuonaForma for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..4 steps

-- 2. Il testo di una nota non si perde mai: il suo segno sta sempre su un carattere del documento.
assert NienteTestoPerso { always all p: Made | one p.home and p.home in live }
check NienteTestoPerso for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps
assert NienteTestoPersoPassando { Choice.onDelete = Pass implies always all p: Made | one p.home and p.home in live }
check NienteTestoPersoPassando for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..4 steps

-- 3. Unendo, le due note si fondono: dopo l'unione stanno nello stesso paragrafo.
assert UnireFonde {
  always all i: Int, p, q: Made, a, b: Tok |
    (a = p.home and b = q.home and Text.toks[i] in Nl and same[a, Text.toks[i]] and ix[b] = i.add[1] and merge[i]) implies
      after (a in live and b in live implies same[a, b])
}
check UnireFonde for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps

-- 4. Riscrivere l'a capo nello stesso punto separa di nuovo le note che l'unione aveva fuso.
assert RiscrivereSepara {
  always all i: Int, n: Nl, p, q: Made |
    (not same[p.home, q.home] and merge[i] and after split[i, n]) implies
      after after not same[p.home, q.home]
}
check RiscrivereSepara for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps

-- 5. Spezzando un paragrafo in un punto che non è un punto ricordato, tutta la sua nota resta al primo.
assert DividereAltroveTiene {
  always all i: Int, n: Nl, p: Made, s: Tok |
    (s = startOf[Text.toks[i]] and p in note[s] and Text.toks[i] != s and Text.toks[i] not in Piece.home and split[i, n])
      implies after (p in note[s])
}
check DividereAltroveTiene for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps

-- Controprove: i casi dei controlli 3–5 si possono costruire.
run CasoUnire {
  eventually (
  some i: Int, p, q: Made | Text.toks[i] in Nl and same[p.home, Text.toks[i]] and ix[q.home] = i.add[1] and merge[i]
  )
} for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps
run CasoRiscrivere {
  eventually (
  some i: Int, n: Nl, p, q: Made | not same[p.home, q.home] and merge[i] and after split[i, n]
  )
} for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps
run CasoDividere {
  eventually (
  some i: Int, n: Nl, p: Made, s: Tok | s = startOf[Text.toks[i]] and p in note[s] and Text.toks[i] != s and
    Text.toks[i] not in Piece.home and split[i, n]
  )
} for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps

-- 4 bis. Con l'ordine dei segni e la regola «passa», riscrivere l'a capo separa sempre di nuovo le note.
assert RiscrivereSeparaPassando {
  Choice.onDelete = Pass implies always all i: Int, n: Nl, p, q: Made |
    (not same[p.home, q.home] and merge[i] and after split[i, n]) implies
      after after not same[p.home, q.home]
}
check RiscrivereSeparaPassando for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps

-- Controprova di 4 bis: proprio il caso limite trovato prima (paragrafo vuoto con una nota, unito al seguente
-- che ne ha un'altra, poi l'a capo riscritto) si può costruire.
run CasoParagrafoVuoto {
  Choice.onDelete = Pass
  eventually (some i: Int, n: Nl, p, q: Made | p.home = Text.toks[i] and p.home in Nl and q.home = Text.toks[i.add[1]]
              and merge[i] and after split[i, n])
} for 3 but 5 Word, 3 Nl, 2 Piece, 7 seq, 1..5 steps
