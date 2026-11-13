# ADR-G: Administration empty state and reader acquisition

- Status: Proposed
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 / #3

## Context

Card administration needs a physical card in a direct reader. When none is present, the
panel still rendered its inputs: a "Select card" title, an empty combo box, a "Details"
heading with nothing under it. This read as broken, not as a state. Worse, a person who
does not own a reader at all had no path forward from this screen, and the one true quirk
of the hardware, that a Keycard Shell (USB) connection is for signing and accounts and does
not expose administration, was buried in a long sentence above the title.

## Decision

Treat "no administrable card" as a first-class empty state, and make acquiring a reader a
path from it.

1. When there is no administrable card, hide the inputs (picker, Details heading) and show
   a centered empty state: a short title ("No Keycard to administer") and one line of
   guidance ("connect it over USB in a card reader; a Keycard Shell is signing-only, move
   its card into a reader").
2. The empty state carries the **reader-acquisition action** directly: a "Get a reader"
   link to the Keycard desktop reader page, with a copy button that copies the URL (clicking
   the link also copies and confirms, since opening an external browser may be blocked in
   the plugin sandbox).
3. While a card **is** present, the same guidance is one tap away: a "How to connect a card"
   link at the end of the "Select card" title opens a help modal that explains the Shell
   quirk and carries the same "Get a reader" link + copy.
4. Remove the long instructional sentence that sat above the title; its content now lives in
   the modal and the empty state, where it is contextual rather than permanent chrome.

Design lens (onboarding as capacity, from the virtual-world material): a person who arrives
at administration without the hardware is unabsorbed demand. The screen should hand them the
next step, not a dead form.

## Consequences

Positive:

- The no-card screen is a legible state, not a broken-looking form.
- The reader purchase page is one tap from the place you discover you need it, online and
  offline-copyable.
- The Shell-vs-reader quirk is explained where it matters (when connecting), not as a
  permanent wall of text.

Costs:

- The "Get a reader" link points at an external page. Opening it uses
  `Qt.openUrlExternally`, which the sandbox may refuse; the copy path is the reliable
  fallback and is always offered.
- A URL to an external store is baked into the UI; if the product page moves, the link and
  the copied value must be updated together (they share one string today).

## Alternatives considered

1. Keep the inputs visible and just disable them when empty. Rejected: a disabled picker and
   an empty "Details" still read as broken and offer no way forward.
2. Only a text hint, no acquisition link. Rejected: it tells the user what is wrong without
   helping; the reader link closes the loop.
