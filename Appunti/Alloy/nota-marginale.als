-- GRIFFR · esperimento Alloy per la tappa 4 (flottante derivato: «trova la quinta parola e crea una nota marginale»).
--
-- Che cosa si modella: i paragrafi del corpo con la loro identità, le parole in ordine, e il contenuto scritto
-- dall'autore per la nota, legato al paragrafo che la «possiede». Le regole d'identità sono quelle di oggi in
-- Sources/Typesetting/DocumentStore.swift (ParagraphID):
--   · scrivendo dentro un paragrafo l'identità non cambia;
--   · spezzandolo, l'identità la tiene la parte con il primo carattere, cioè la prima (DocumentStore.resegment;
--     il commento su ParagraphID dice «la parte con più testo», ma il codice e la prova splitAndMerge no);
--   · unendogli il paragrafo seguente, la tiene il primo; il seguente scompare.
-- Annulla non si modella: il deposito rimette una copia dei paragrafi di prima con le loro identità (Change,
-- prova undoRestoresIdentity). Riscrivere a mano un a capo tolto, invece, è un'operazione nuova.
--
-- Domande: la nota resta sempre attaccata a un paragrafo vivo? può raddoppiare? dopo una divisione punta ancora
-- alla sua parola? Togliere un a capo e riscriverlo nello stesso punto rimette le cose com'erano?
--
-- Attenzione: in Alloy `let` è una sostituzione, non un valore salvato: per confrontare uno stato con il seguente
-- la parola si fissa con un quantificatore (`all w: Word | w = target[p] implies after …`).
--
-- Limiti: documenti piccoli (vedi gli scope dei comandi); parole come occorrenze astratte (niente caratteri,
-- niente note a piè di pagina, niente sezioni); nessuna divisione all'inizio di un paragrafo.

module notaMarginale

-- Un'occorrenza di parola: sta al più in un posto del documento.
sig Word {}

sig Para {
  var words: seq Word
}
-- I paragrafi nel documento, e quelli che lo sono stati almeno una volta (un'identità non si riusa).
var sig Live in Para {}
var sig Used in Para {}

-- Il contenuto della nota scritto dall'autore, con il paragrafo che lo possiede.
sig Note {
  var owner: lone Para
}

one sig Doc {
  var order: seq Para
}

-- Che cosa fa «unisci» delle note del paragrafo che scompare: oggi niente (seguono l'identità), oppure le sposta
-- sul paragrafo che resta.
abstract sig Policy {}
one sig Follow, Move extends Policy {}
one sig Choice { policy: one Policy }

-- La parola a cui la nota si aggancia: la quinta del paragrafo (gli indici partono da 0).
fun target[p: Para]: lone Word { p.words[4] }

fun earlier[a, b: Para]: Para { Doc.order.idxOf[a] < Doc.order.idxOf[b] => a else b }

pred wellFormed {
  Doc.order.elems = Live
  not Doc.order.hasDups
  Live in Used
  all p: Para - Live | no p.words
  all p: Live | not p.words.hasDups
  all disj p, q: Live | no p.words.elems & q.words.elems
}

-- Le proprietà che si vogliono vere sempre.
pred ownersLive { all n: Note | one n.owner and n.owner in Live }
pred oneNoteEach { all p: Para | lone owner.p }

pred init {
  wellFormed
  ownersLive
  oneNoteEach
  Used = Live
}

-- Nessun cambiamento fuori da `changed`.
pred frameWords[changed: set Para] { all r: Para - changed | r.words' = r.words }

pred insertWord[p: Para, i: Int, w: Word] {
  p in Live
  w not in Live.words[Int]
  i >= 0 and i <= #p.words
  p.words' = p.words.insert[i, w]
  frameWords[p]
  Live' = Live and Used' = Used and Doc.order' = Doc.order and owner' = owner
}

pred deleteWord[p: Para, i: Int] {
  p in Live
  i in p.words.inds
  p.words' = p.words.delete[i]
  frameWords[p]
  Live' = Live and Used' = Used and Doc.order' = Doc.order and owner' = owner
}

-- Spezza `p` prima della parola `i`: nasce `q`, un'identità nuova, con la seconda parte. `p` tiene la prima.
pred split[p: Para, i: Int, q: Para] {
  p in Live
  q not in Used
  i > 0 and i < #p.words
  p.words' = p.words.subseq[0, i.sub[1]]
  q.words' = p.words.subseq[i, p.words.lastIdx]
  Doc.order' = Doc.order.insert[Doc.order.idxOf[p].add[1], q]
  frameWords[p + q]
  Live' = Live + q
  Used' = Used + q
  owner' = owner
}

-- Unisce a `p` il paragrafo che lo segue: `p` resta, il seguente scompare.
pred merge[p: Para] {
  p in Live
  let i = Doc.order.idxOf[p], q = Doc.order[i.add[1]] {
    some q
    p.words' = p.words.append[q.words]
    -- Le parentesi servono: il punto lega più del #.
    #p.words' = (#p.words).add[#q.words]
    no q.words'
    frameWords[p + q]
    Live' = Live - q
    Used' = Used
    Doc.order' = Doc.order.delete[i.add[1]]
    Choice.policy = Follow implies owner' = owner
    Choice.policy = Move implies owner' = owner - (Note -> q) + (owner.q -> p)
  }
}

pred stutter {
  words' = words
  Live' = Live and Used' = Used and Doc.order' = Doc.order and owner' = owner
}

fact traces {
  init
  always (stutter
          or (some p: Para, i: Int, w: Word | insertWord[p, i, w])
          or (some p: Para, i: Int | deleteWord[p, i])
          or (some p, q: Para, i: Int | split[p, i, q])
          or (some p: Para | merge[p]))
}

-- 0. Il modello non è vuoto: un documento con una nota agganciata che si spezza e si riunisce.
run Esempio {
  some n: Note | some target[n.owner]
  eventually (some p, q: Para, i: Int | split[p, i, q])
} for 3 but 6 Word, 5 seq, 1..4 steps

-- 1. Le operazioni conservano la buona forma del documento (controllo del modello stesso).
assert BuonaForma { always wellFormed }
check BuonaForma for 3 but 6 Word, 5 seq, 1..3 steps

-- 2. Una nota è sempre attaccata a un paragrafo del documento.
assert NotaSempreAttaccata { always ownersLive }
check NotaSempreAttaccata for 3 but 6 Word, 5 seq, 1..4 steps

-- 3. Un paragrafo non ha mai due note.
assert MaiDueNote { always oneNoteEach }
check MaiDueNote for 3 but 6 Word, 5 seq, 1..4 steps

-- 4. Dopo una divisione, se la parola della nota c'è ancora, la nota punta ancora lei.
assert DivisioneTieneLaParola {
  always all p, q: Para, i: Int, n: Note |
    (n.owner = p and some target[p] and split[p, i, q]) implies
      (all w: Word | w = target[p] implies after (w in Live.words[Int] implies target[n.owner] = w))
}
check DivisioneTieneLaParola for 3 but 6 Word, 5 seq, 1..4 steps

-- 5. Togliere un a capo e riscriverlo nello stesso punto rimette ogni nota sul paragrafo che ha la sua parola.
assert RiscrivereRimette {
  always all p: Para, n: Note, w: Word, k: Int |
    (n.owner = Doc.order[Doc.order.idxOf[p].add[1]] and w = target[n.owner] and k = #p.words and merge[p] and
     after (some r: Para | split[p, k, r])) implies
      after after (w in Live.words[Int] implies target[n.owner] = w)
}
check RiscrivereRimette for 3 but 7 Word, 7 seq, 1..3 steps

-- Controprova di 4: si cerca direttamente il caso che 4 vieta.
run CasoDivisione {
  some p, q: Para, i: Int, n: Note | n.owner = p and some target[p] and split[p, i, q] and
    (some w: Word | w = target[p] and after (w in Live.words[Int] and target[n.owner] != w))
} for 3 but 6 Word, 5 seq, 1..4 steps

-- 2–5 con le due regole per «unisci»: si vede che cosa dipende dalla scelta e che cosa no.
assert AttaccataSeguendo { Choice.policy = Follow implies always ownersLive }
assert AttaccataSpostando { Choice.policy = Move implies always ownersLive }
assert MaiDueSeguendo { Choice.policy = Follow implies always oneNoteEach }
assert MaiDueSpostando { Choice.policy = Move implies always oneNoteEach }
check AttaccataSeguendo for 3 but 6 Word, 5 seq, 1..4 steps
check AttaccataSpostando for 3 but 6 Word, 5 seq, 1..4 steps
check MaiDueSeguendo for 3 but 6 Word, 5 seq, 1..4 steps
check MaiDueSpostando for 3 but 6 Word, 5 seq, 1..4 steps

-- Controprova di 5: il caso si può costruire (altrimenti 5 passerebbe solo perché impossibile).
run CasoRiscrivere {
  some p: Para, n: Note, k: Int | n.owner = Doc.order[Doc.order.idxOf[p].add[1]] and some target[n.owner] and
    k = #p.words and merge[p] and after (some r: Para | split[p, k, r])
} for 3 but 7 Word, 7 seq, 1..3 steps
