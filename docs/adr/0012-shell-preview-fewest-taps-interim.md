# ADR-L: Preview one account at a time on a Shell (fewest-taps interim)

- Status: Accepted
- Date: 2026-11-14
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2; upstream logos-co/logos-keycard-shell-module#9, keycard-tech/keycard-shell#237

## Context

Adding accounts previews a page of derivation indexes read from the device. The code requested a
fixed page of **5** for both transports. On a Keycard Shell every exported public key needs its own
on-device confirmation, so a 5-account preview cost 5 taps, on top of ~2 taps of first-use overhead
per connection (master-key verify + the "Connect wallet" consent). Measured on real hardware: 5
addresses = 5 taps; 1 address on a fresh connection = 3 taps.

The Shell firmware author (bitgamma) confirmed on keycard-tech/keycard-shell#237 that per-export
confirmation is intentional, and that the correct fix is host-side: export the account xpub at
`m/44'/60'/0'` once and derive the leaves host-side (one tap, any number of addresses). That fix
lives in `keycard_shell_module` (the per-leaf export is inside it; `keycard_ui` only passes leaf
paths and shows results), and is filed as logos-co/logos-keycard-shell-module#9. It is not
something `keycard_ui` can do alone.

## Decision

Until the module exports the account xpub, make the Shell preview cost the fewest taps the current
module allows:

1. Preview **one** account per page on a Shell, five on a card (PC/SC, which has no per-key tap):
   `addSheet.pageSize = root.shell ? 1 : 5`. Next/Previous page by `pageSize`; the page label reads
   "Index N" at size 1.
2. Set expectations in the copy: the Shell step explains that each account is a separate public-key
   request confirmed on the device, and that "Next" fetches more one at a time. The "working"
   message says "Press OK on the Shell to confirm the public-key request".

This is explicitly an interim measure. It trades the fuller 5-account preview for the minimum device
friction on the common "add one account" flow (one address shown per confirmation). It is to be
**reverted to a single multi-address preview once the module exports the account xpub** (issue #9),
at which point one tap yields any number of addresses.

## Consequences

Positive:

- The common add-one-account flow on a Shell is the fewest taps the module currently permits.
- No wasted exports: the user pays a tap per address only for addresses they actually page to.
- The copy stops the repeated on-device confirmations from reading as a glitch.

Costs:

- The Shell picker shows one address at a time; paging for more costs a tap each. This is worse than
  the eventual xpub flow and is accepted only as an interim.
- A transport-dependent page size (1 vs 5) is a small special-case in the picker. It is removed when
  #9 lands.

## Alternatives considered

1. Keep the 5-account page on a Shell. Rejected: 5 taps to preview, when most people add one
   account; the rare addresses crowd the common one, at a tap each.
2. Do the xpub-export-and-derive in `keycard_ui`. Not possible: the per-leaf export is inside
   `keycard_shell_module`; the UI only passes paths. The fix is filed against that module (#9).
3. Fix nothing, just reword the copy. Rejected: the copy helps, but five unavoidable taps for the
   common case is the actual cost to cut now.
