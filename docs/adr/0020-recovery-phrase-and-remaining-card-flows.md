# ADR-T: Recovery-phrase and the remaining card operations in the guided flow

- Status: Accepted
- Date: 2026-11-15
- Scope: `keycard_ui` (UI only; CardFlow + CardAdministration; no backend change)
- Issue: #2 (extends ADR-0018; completes the conversion begun there)

## Context

ADR-0018 put the PIN-centric operations on a guided, one-input-per-screen flow. The remaining
operations — Set up card, Read/Write data, and the three recovery-phrase operations (Check, Import,
Create) — stayed on the old single form. The phrase operations are the most sensitive: the old form
generated a seed and showed it in clear with no warning, took the whole phrase as one text blob, and
had no backup check.

## Decision

Convert every remaining operation to `CardFlow`, adding the step kinds and one special phase they need.

**New step kinds**: `phrase` (a `PhraseGrid` of 12-24 word fields; valid when complete), `check` (a
checkbox; valid when ticked), `choice` rendered as **radio buttons** (one tap, no dropdown), and a
`text` step may carry a `defaultValue` + `defaultLabel` to offer a **"use the default" prefill**
checkbox (used for the Keycard pairing password, `KeycardDefaultPairing`, verified in the module
source). A flow containing a phrase grid uses a **taller, scrollable** modal.

**Converted operations**:

- **Set up card** (initialize) — PIN/PUK with a pairing-password step on 3.x only (conditional on
  `secureChannel`).
- **Read card data** → a result screen showing the hex; **Write card data** → area + hex + PIN + typed
  WRITE.
- **Check recovery phrase** — phrase grid + optional passphrase + PIN → match / no-match.
- **Import recovery phrase** — phrase grid + passphrase + backup confirm + PIN.
- **Create recovery phrase** — the two-phase, security-sensitive flow below.

**Create flow** (word count → PIN → generate → reveal → confirm → load):

1. The phrase is **generated** on the card ("Generating your recovery phrase…", not "Writing…": the
   working message is now per-operation).
2. **Reveal**: the words are **hidden behind a privacy warning and a Reveal button** (no words until
   the person acts), then shown as a **numbered three-column list** for writing down.
3. **Confirm**: the person re-enters **three random words by position**; a wrong word shows an error
   once the field loses focus (Status-style), and **Load** stays disabled until all three match.
4. **Load**: the generated phrase is loaded onto the card with the PIN already entered. The seed lives
   in memory only until the flow closes.

**Admin fixes alongside**: the Card fingerprint row is shortened (`shortHex`); the action selection no
longer rides a hidden combo (ADR-0018 note); "card" dropped from the action labels; modal heights
trimmed (base 380, tall 500, with Change PIN as the reference).

## Consequences

Positive:

- Every card operation shares one guided framework with the same header, fixed modal, and error
  handling.
- The seed is never shown without an explicit reveal and a privacy warning, and a backup is proven
  before the keys are loaded — the old clear-text dump is gone.

Costs / follow-ups:

- The reveal uses an **opaque cover**, not a frosted blur; the security outcome (nothing shown until
  reveal) is the same, and a `MultiEffect` blur can replace it if the look is wanted.
- **Create and Import only appear on a card that is set up but keyless**; the backend hides them when
  keys are present, so they can only be exercised on a fresh/erased card.
- Word confirmation checks the typed word against the generated phrase only; it does not also validate
  against the BIP39 word list (not needed, since it must match an exact generated word).

## Alternatives considered

1. **Keep phrase operations on the old form.** Rejected: the clear-text seed with no warning is the
   worst screen in the app; it is exactly what the guided flow is for.
2. **A real Gaussian blur over the seed.** Deferred: an opaque cover is simpler, reliable, and hides
   the words completely; blur can be added later.
3. **Confirm by re-typing the whole phrase.** Rejected as heavier than Status's few-word check for the
   same assurance.
