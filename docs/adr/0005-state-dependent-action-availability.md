# ADR-E: State-dependent action availability, from the Status mapping

- Status: Accepted
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; two backend gaps noted as upstream dependencies)
- Issue: #2 (refines ADR-A's action list)

## Context

ADR-A presents the administrative operations as a visible, risk-grouped list, computed
from the selected card's `choices`. The original `choices` gated only coarsely: it hid
operations behind "initialized" and the 3.x "paired" check, but otherwise showed almost
every operation for any usable card.

On a real card this showed actions that cannot apply to the card's current state:

- Seed-loading actions (Create recovery phrase, Import recovery phrase, Generate keys)
  were shown on a card that already holds a seed, where the module refuses them
  ("refuses to overwrite existing keys").
- Key-present actions (Check recovery phrase, Erase keys) were shown on an empty card with
  no seed to check or erase.
- Unblock PIN was shown on a card whose PIN is not blocked.
- A PIN-locked card still offered PIN-gated actions that cannot run until it is unblocked.

The user's point: not all actions apply to every state, and a correct map of state to
action already exists in a proven implementation.

## Decision

Gate the action list by card state, mirroring the Status desktop Keycard management UI,
then reduce to the actions our `keycard_module` exposes. The full map is in
`docs/keycard-state-action-map.md`.

Sources mirrored (the "latest Keycard implementation" per the request):

- Card states: `status-im/status-keycard-qt`, `src/session/session_state.h`
  (EmptyKeycard, BlockedPIN, BlockedPUK, Ready, Authorized, ...), which that file states
  matches `status-keycard-go` exactly.
- Per-action visibility: `status-im/status-desktop`,
  `ui/app/AppLayouts/Profile/views/keycard_new/DetailsView.qml`, with the state flags in
  `.../helpers/KeycardStateInfo.qml` (`onlyPinSet`, `hasKeyPair`, `isBlockedPIN`,
  `isBlockedPUK`, `isEmpty`).

The rules, in our card fields (`initialized`, `keyUid`, `secureChannel`, `paired`,
`pinRetries`, `capabilities`):

1. `!initialized` → only `initialize`.
2. 3.x and `!paired` → only `pair`.
3. `pinRetries === 0` (locked) → only `unblock_pin` and `factory_reset`; every PIN-gated
   action is hidden. (Status: `isBlockedPIN`.)
4. No seed (`!keyUid`) → seed provisioning (`generate_phrase`, `load_phrase`,
   `generate_key`); not the key-present actions. (Status: provisioning visible on
   `isEmpty || onlyPinSet`.)
5. Has seed (`keyUid`) → `verify_phrase`, `remove_key`; not the provisioning actions.
   (Status: `hasKeyPair`.)
6. Any usable card (has PIN, not locked) → `change_pin`, `change_puk`, 3.x pairing
   management, `set_name`, `set_ndef`, `read_data`, `write_data`. (Status: `hasKeyPair ||
   onlyPinSet`, not blocked.)
7. `factory_reset` on any initialized, capable card, and as the escape from a locked card.

Actions dropped by the "our module only" filter: Status's `Login`, `Sign`,
`ExportPublicKey`/`ExportExtendedPublicKey` (the wallet/accounts flow, not administration),
"Unblock with recovery phrase" (we expose only PUK unblock), and the Status-wallet
"move/add key pair" flows.

## Consequences

Positive:

- The list only ever offers actions the selected card can actually perform, matching a
  proven reference rather than ad-hoc gating.
- Destructive-by-confusion paths shrink: you cannot pick "Erase keys" on an empty card or
  a seed-loading action on a card that holds a seed.
- The gating has a single documented source of truth (the map doc), traceable to Status.

Costs and limits:

- Two states Status gates on are not fully gatable here, because `keycard_module.cards()`
  does not return the needed fields (see the upstream gaps below). Specifically BlockedPUK
  and "no free pairing slots". The actions remain safe (the module rejects an impossible
  call and `factory_reset`, the correct exit, stays offered), but the list cannot pre-hide
  them the way Status does.

## Upstream dependencies (keycard_module)

Recorded in `docs/upstream-keycard-module-gaps.md`:

1. `cards()` should return `pukRetries`, so a BlockedPUK card can be gated to factory reset
   only (as Status's `isBlockedPUK` does), without first running `status`.
2. `cards()` should return the free-pairing-slot count, so "no free pairing slots" can be
   surfaced the way Status's `noKnownAndNoAvailablePairingSlots` is.

Neither blocks this decision; both would let the UI match Status exactly.

## Alternatives considered

1. Keep the coarse gating and rely on the submit-time guards and module errors to stop
   impossible actions. Rejected: it shows actions that cannot work and relies on an error
   after the fact, which is exactly the "not all actions apply" problem.
2. Derive availability from a card-state enum computed in the UI. Deferred: the field-level
   predicates are clear enough; a named-state layer can come with the upstream fields.
