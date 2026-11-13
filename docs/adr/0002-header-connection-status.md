# ADR-B: Header connection status, from observable signals

- Status: Accepted
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; one backend gap noted as an upstream dependency)
- Issue: #3 (connection-state labels beside the title)

## Context

The app header shows a single connection chip (a `LogosBadge`) summarising what the app
can see of the card hardware, next to the title and the refresh button.

The view derives this only from what the backend reports:

- `backend.cardsJson` — `keycard_module.cards()`, documented as "the readers holding a
  card", i.e. only readers that currently have a card inserted.
- `backend.shellDevicesJson` — connected Keycard Shell devices over USB.

There is no signal for a bare reader. `cards()` returns nothing for an empty reader, and
there is no `readers()` method, so an empty reader and no reader at all are
indistinguishable from the UI.

## Problem

The desired chip has three physical states with distinct colours:

1. A card is in a reader — green, "Card connected".
2. A reader is connected but empty — yellow, "Card reader connected".
3. No reader at all — red, "No reader detected".

State 1 is directly observable (`cards().length > 0`). States 2 and 3 are not
distinguishable with the current contract: both produce an empty `cards()` and no shell.

## Decision

Show only states the app can actually observe, and never assert a hardware fact the
backend has not confirmed.

1. Card present (`cards.length > 0`): "Card connected", success colour.
2. Shell present (`shellDevices.length > 0`, no card): "Shell connected", success colour.
3. Neither: "No card detected", warning colour. This is the honest union of "empty
   reader" and "no reader": we know there is no card; we do not claim whether a reader is
   present.
4. Before the view module is ready: "Starting" (neutral), becoming "Not responding"
   (warning) after a grace window (see the startup-status work).

We deliberately do not print "No reader detected" (red) while a reader may be plugged in,
and we do not print "Card reader connected" (yellow) while the reader may be absent.
Either would state, as fact, something the app cannot verify.

## Consequences

Positive:

- Every label is true of what the app can see. "Card connected" (green) is reliable and
  is the state the user cares about most.
- No false hardware claims.

Costs:

- The two empty states (empty reader vs no reader) collapse into one, so the full
  red/yellow/green split the design asks for is not delivered yet.

## Dependency (upstream)

Splitting state 2 from state 3 requires `keycard_module` to report connected readers that
hold no card (a `readers()` method, or empty-reader entries in `cards()`). This is a small
module/contract addition. When it lands, the chip gains the red "No reader detected" and
yellow "Card reader connected" states with no further UI redesign. Tracked as an upstream
ask to the module owner.

## Alternatives considered

1. Assume a reader is usually present and show yellow "Card reader connected" for the
   empty state. Rejected: it mislabels the common "I unplugged the reader" case as a
   reader being connected.
2. Assume no reader and show red "No reader detected" for the empty state. Rejected: it
   mislabels "reader connected, no card yet" as an error with no reader.
3. Probe PC/SC for readers directly from the UI. Rejected: the UI must not reach around
   its module to a second source of truth; reader enumeration belongs in `keycard_module`.
