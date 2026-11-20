# ADR-R: Guided, one-input-per-screen flows for card operations

- Status: Accepted
- Date: 2026-11-15
- Scope: `keycard_ui` (UI only; two new QML components + CardAdministration routing; no backend change)
- Issue: #2

## Context

Card administration presented every operation as a single scrolling form in one dialog, with all
fields (current PIN, new PIN, repeat, PUK, pairing, name, confirmation, …) shown at once and gated by
one large `enabled` expression. PINs were bare password text fields. There was no step structure, no
sense of which card you were operating on, no distinct success / failure state, and a wrong PIN was a
flat error line with no attempts-remaining and no route into PUK unblock.

The Status Keycard flows (which this project's designer built) are the reference: circles for PIN /
PUK entry, one input per screen, a header that keeps the flow name, the step and the card in view, a
"writing" state, and success / in-step error handling with attempts and block routing.

## Decision

Introduce a guided flow and move card operations onto it, keeping the single-form dialog only for the
operations not yet converted.

**`PinDots`** — a Status-style `StatusPinInput`: a row of circles that fill as digits are typed,
digit-only (validator + `Qt.ImhDigitsOnly`), fixed length (6 for a PIN, 12 for a PUK), with an error
tint and an `entered` signal. The value lives in an invisible `TextInput`; the circles are the only
visual and the digits are never shown. Accessibility announces the count entered, not the digits.

**`CardFlow`** — a step machine with a fixed layout:

1. **Title line** (persists across every step and phase): the flow name on the left, the card being
   operated on (name + Wallet ID) on the right.
2. **Centred step**: "Step N of M", the step title, the step description.
3. **One input per step**, by step kind: `pin` / `puk` (PinDots), `text` (a field; `secret` masks it,
   `digitsOnly` / `minLen` / `maxLen` constrain it, `match` confirms a repeat), `confirm` (a typed
   word such as RESET / ERASE / NO BACKUP), `info` (a red warning to acknowledge).
4. **Fixed modal size** — the dialog height is fixed and each phase is centred in one body, so a tip
   or an error never resizes it; a reserved line holds the error-or-tip text.
5. **Phases**: input → **working** ("writing to the card") → **success** (Done) or **error**.
6. **Wrong-secret handling** (verified against `keycard_module`): a failure returns
   `{ok:false, code:"WrongSecret", error}` with the count only in the message, so the remaining
   attempts are read back authoritatively from a no-PIN `status` call (`pinRetries` / `pukRetries`).
   A wrong PIN stays on the step with "N attempts left"; at 0 the PIN is blocked and the flow offers
   **Unblock PIN** (switching into the PUK flow); a blocked PUK is terminal (factory reset only). A
   wrong-length PIN never reaches the card — the module rejects it before counting an attempt, and
   fixed-length PinDots never sends one.
7. Smaller rules: new PIN must differ from the current one (change PIN); a soft nudge on a trivially
   weak new PIN; the dots clear and refocus after any validation error so the field is ready to
   retype; the error clears on the first keystroke.

**Converted so far**: the PIN-centric trio (Change PIN, Change PUK, Unblock PIN) and the plain
step-sequence operations (Update card name, NFC text, Pair this app, Change pairing password, Remove a
pairing slot, Generate keys without backup, Erase keys from card, Factory reset card).
`CardAdministration` routes these to `CardFlow` by action id; everything else still opens the form.

## Consequences

Positive:

- One input at a time, with the flow, step and card always on screen; PIN entry matches the rest of
  the Keycard ecosystem (circles, digit-only, fixed length).
- Wrong PIN is recoverable in place with a real attempts count and a route to unblock, instead of a
  dead error line.
- A single, stable modal size across input, writing, success and failure.

Costs / follow-ups:

- **Not all operations are converted.** Set up card (initialize — conditional multi-PIN/PUK/pairing),
  Create / Import / Check recovery phrase (phrase grid + generated-word display + backup confirm), and
  Read / Write card data (hex + result display) need result-display and phrase-grid step kinds; they
  stay on the form until a second pass adds those kinds to `CardFlow`.
- The modal height (404) and the text-field width are layout constants; a DS token would be tidier.
- `CardFlow` holds entered secrets in a JS map for the life of the flow (cleared on close), as the
  old form held them in field text.

## Alternatives considered

1. **Keep the single form, just restyle it.** Rejected: the one-input-per-screen flow is the whole
   point of the Status pattern and is what makes attempts/block routing and destructive confirmations
   legible.
2. **A bespoke dialog per operation.** Rejected: the operations are the same handful of step kinds in
   different orders; one step machine keeps them consistent and is where the next operations plug in.
3. **An on-screen numeric keypad (as on mobile).** Deferred: Basecamp is desktop-first, so PinDots
   takes the physical keyboard; a soft keypad can be added for touch later.
