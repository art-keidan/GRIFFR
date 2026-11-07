-- GRIFFR · esperimento Alloy 3: l'occhio della progettazione del capoverso («dal vivo» su tutti o solo qui).
--
-- Che cosa si modella, seguendo Sources/WordProcessor/EditorWindowController+Progetta.swift (commit 16aed52):
--   · capoversi con uno stile; il capoverso evidenziato (il cursore);
--   · la portata: Stile o Capoverso (¶); l'occhio: pieno (dal vivo su tutti) o barrato (dal vivo solo qui);
--   · la bozza: modifiche di stile, ciascuna di un genere: Attributo (rientri, spazi… scritti nel testo dal
--     restyle) o Direttiva (tenuta delle righe, distanza d'apertura, formule contestuali: lette dall'impaginazione
--     negli stili delle opzioni, `options.styles`);
--   · ciò che le pagine mostrano: una fotografia calcolata da `showDraft`, e non ricalcolata altrimenti.
--
-- Il codice di oggi (variante Codice):
--   · showDraft: un Attributo si vede su tutti i capoversi del suo stile con l'occhio pieno, solo sull'evidenziato con
--     l'occhio barrato (restyle limitato al capoverso); una Direttiva si vede su tutti comunque (`document.styles = sheet`);
--   · showDraft si chiama dopo una modifica, cambiando l'occhio, e dopo una ricomposizione del documento; NON quando il
--     cursore passa a un altro capoverso, né quando si sceglie ¶ o si torna allo stile.
-- La regola voluta (variante Corretta): si vede ciò che dicono lo stato e l'occhio, sempre.
--
-- Limiti: 3 capoversi, 2 stili, 3 modifiche, 6 passi; nessun valore numerico, nessun salvataggio.

module occhioDalVivo

abstract sig Bool {}
one sig True, False extends Bool {}

sig Style {}
sig Para { style: one Style }

abstract sig Kind {}
one sig Attribute, Directive extends Kind {}

-- Una modifica di stile nella bozza.
sig Edit { target: one Style, kind: one Kind }

abstract sig Scope {}
one sig StyleScope, ParagraphScope extends Scope {}

abstract sig Variant {}
one sig Code, Fixed extends Variant {}

one sig S {
  variant: one Variant,
  var scope: one Scope,
  var live: one Bool,
  var cur: one Para,
  var draft: set Edit,
  -- Ciò che le pagine mostrano: la modifica e si vede sul capoverso p.
  var shown: Edit -> Para
}

-- Ciò che si dovrebbe vedere con lo stato di adesso.
fun wanted: Edit -> Para {
  { e: S.draft, p: Para | p.style = e.target and (S.live = True or p = S.cur) }
}

-- Ciò che calcola showDraft nel codice, nello stato dopo il passo.
fun computedNext: Edit -> Para {
  { e: S.draft', p: Para | p.style = e.target and
      (S.live' = True or p = S.cur' or (S.variant = Code and e.kind = Directive)) }
}

pred showDraft { S.shown' = computedNext }
pred keepShown { S.shown' = S.shown }

pred init {
  S.scope = StyleScope
  S.live = True
  no S.draft
  no S.shown
}

-- Una modifica nella portata dello stile, sullo stile del capoverso evidenziato.
pred edit[e: Edit] {
  S.scope = StyleScope
  e not in S.draft
  e.target = S.cur.style
  S.draft' = S.draft + e
  S.scope' = S.scope and S.live' = S.live and S.cur' = S.cur
  showDraft
}

-- L'occhio: nella portata dello stile passa da pieno a barrato e ritorno; nella portata ¶ riporta allo stile.
pred toggleEye {
  S.draft' = S.draft and S.cur' = S.cur
  S.scope = StyleScope implies {
    S.scope' = StyleScope
    S.live' != S.live
    showDraft
  } else {
    S.scope' = StyleScope
    S.live' = S.live
    S.variant = Code implies keepShown else showDraft
  }
}

pred pickParagraph {
  S.scope' = ParagraphScope
  S.draft' = S.draft and S.live' = S.live and S.cur' = S.cur
  S.variant = Code implies keepShown else showDraft
}

-- Il cursore passa a un altro capoverso.
pred move[p: Para] {
  p != S.cur
  S.cur' = p
  S.draft' = S.draft and S.live' = S.live and S.scope' = S.scope
  S.variant = Code implies keepShown else showDraft
}

pred stutter {
  S.scope' = S.scope and S.live' = S.live and S.cur' = S.cur and S.draft' = S.draft and keepShown
}

fact traces {
  init
  always (stutter or toggleEye or pickParagraph or (some e: Edit | edit[e]) or (some p: Para | move[p]))
}

-- 1. Con l'occhio barrato, nella portata dello stile, la bozza si vede solo sul capoverso evidenziato.
pred onlyHereWhenEyeClosed {
  always ((S.live = False and S.scope = StyleScope) implies S.shown.Para in S.draft and Edit.(S.shown) in S.cur)
}

-- 2. Con l'occhio pieno, ogni modifica si vede su tutti i capoversi del suo stile.
pred everywhereWhenEyeOpen {
  always (S.live = True implies (all e: S.draft, p: Para | p.style = e.target implies p in e.(S.shown)))
}

-- 3. Ciò che si vede corrisponde sempre allo stato.
pred neverStale { always S.shown = wanted }

check CodeOnlyHere { S.variant = Code implies onlyHereWhenEyeClosed } for 3 but 6 steps
check CodeEverywhere { S.variant = Code implies everywhereWhenEyeOpen } for 3 but 6 steps
check CodeNeverStale { S.variant = Code implies neverStale } for 3 but 6 steps
check FixedOnlyHere { S.variant = Fixed implies onlyHereWhenEyeClosed } for 3 but 6 steps
check FixedEverywhere { S.variant = Fixed implies everywhereWhenEyeOpen } for 3 but 6 steps
check FixedNeverStale { S.variant = Fixed implies neverStale } for 3 but 6 steps

-- Controprove: i casi interessanti si possono costruire.
run CaseEyeClosedTwoParagraphs {
  S.variant = Fixed
  eventually (S.live = False and some S.draft and some p: Para | p != S.cur and p.style = S.cur.style)
} for 3 but 6 steps
run CaseMoveWithEyeClosed {
  S.variant = Fixed
  eventually (S.live = False and some S.draft and some p: Para | move[p])
} for 3 but 6 steps
