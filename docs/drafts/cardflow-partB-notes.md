# CardFlow Part B (phrase + data-result flows) — notes

Flows: generate_phrase (Create), load_phrase (Import), verify_phrase (Check).

Key requirements:
- PhraseGrid (12-24 word fields) needs a taller / scrollable modal than the fixed 404 PIN modal.
- generate_phrase is two-phase: choice(word count) -> PIN -> [generate] -> SHOW words + backup
  confirm -> [load_phrase with generated + "BACKED UP"] -> success.
- verify_phrase: PhraseGrid input + passphrase + PIN -> result message (match / no match). No display.
- load_phrase: PhraseGrid input + passphrase + PIN + backup checkbox -> success.

SEED SECURITY (Status pattern, Alisher 2026-11-15): the generated seed words must be BLURRED by
default behind a warning ("Make sure no one is watching / recording your screen"), revealed only on an
explicit action (tap / press-and-hold / Reveal toggle), ideally re-blurring after. The current app
shows the seed with NO warning - fix this in the generate result screen. Apply the same care to
verify/import where words are visible.
