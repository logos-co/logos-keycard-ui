# Keycard state → action map

Which administrative actions apply to which card state. The gating is taken from the
Status desktop Keycard management UI (`status-im/status-desktop`
`ui/app/AppLayouts/Profile/views/keycard_new/DetailsView.qml` and the state flags in
`.../helpers/KeycardStateInfo.qml`), and the state names from the latest Keycard
implementation (`status-im/status-keycard-qt` `src/session/session_state.h`, which mirrors
`status-keycard-go`). The action set is then reduced to the actions our
`keycard_module` actually exposes (`cards()` fields + the `administer` schema).

## Card states

Status names these; we derive each from the fields `keycard_module.cards()` returns per
card (`initialized`, `keyUid`, `secureChannel`, `paired`, `pinRetries`, `capabilities`).

| Status state | Status flag | Our derivation | Meaning |
|---|---|---|---|
| EmptyKeycard (no PIN) | `isEmpty` | `!initialized` | no credentials, no seed |
| INITIALIZED, no seed | `onlyPinSet` = `initialized && keycardUid && !keyUid` | `initialized && !keyUid` | PIN set, no seed |
| Ready / Authorized | `hasKeyPair` = `keycardUid && keyUid` | `initialized && keyUid` | has a seed |
| BlockedPIN | `isBlockedPIN` | `pinRetries === 0` | PIN locked (3 fails) → PUK unblock |
| BlockedPUK | `isBlockedPUK` | `pukRetries === 0` (status only) | PUK frozen (5 fails) → reset only |
| 3.x not paired | — | `secureChannel === 1 && !paired` | needs pairing before any op |

Note: `pukRetries` is not in `cards()` (only in the `status` result), so BlockedPUK is
not distinguishable at the action-list level; factory reset, its only exit, stays offered.
An upstream improvement would add `pukRetries` (and free-slot count) to `cards()`.

## Action availability (our module's actions only)

Columns are the operable states. "Reset-only" states (BlockedPIN, BlockedPUK) collapse to
their recovery actions. `status` and `check_identity` are read-only info (no PIN), shown as
buttons in the Card status section, available in every state; they are not in this table.

| Our action | Status flow (equiv) | UNINIT `!init` | no-seed `onlyPinSet` | has-seed `hasKeyPair` | BlockedPIN |
|---|---|:--:|:--:|:--:|:--:|
| `initialize` | Recover (setup) | ✓ | — | — | — |
| `pair` (3.x unpaired) | implicit pairing | — | ✓* | ✓* | — |
| `generate_phrase` | — (our extra) | — | ✓ | — | — |
| `load_phrase` | Import from recovery phrase | — | ✓ | — | — |
| `generate_key` | Import new key pair (on-card) | — | ✓ | — | — |
| `verify_phrase` | — (our extra) | — | — | ✓ | — |
| `remove_key` | — (our extra; Status resets) | — | — | ✓ | — |
| `change_pin` | Change PIN | — | ✓ | ✓ | — |
| `change_puk` | Set or change PUK | — | ✓ | ✓ | — |
| `unblock_pin` | Unblock with PUK | — | — | — | ✓ |
| `change_pairing_password` (3.x) | — (our extra) | — | ✓ | ✓ | — |
| `unpair` (3.x) | — (our extra) | — | ✓ | ✓ | — |
| `set_name` | Rename (metadata) | — | ✓ | ✓ | — |
| `set_ndef` | — (our extra) | — | ✓ | ✓ | — |
| `read_data` | GetKeycardMetadata | — | ✓ | ✓ | — |
| `write_data` | — (our extra) | — | ✓ | ✓ | — |
| `factory_reset` | Factory reset | — | ✓ | ✓ | ✓ |

`*` only while the 3.x card is unpaired; once paired the action disappears and the rest
appear. `pair` is the only action shown for an unpaired 3.x card.

## The rules, stated plainly

1. **No PIN yet** (`!initialized`): only `initialize`.
2. **3.x, not paired**: only `pair`.
3. **PIN locked** (`pinRetries === 0`): only `unblock_pin` and `factory_reset`. Everything
   that needs the current PIN is hidden.
4. **Seed provisioning** (`generate_phrase`, `load_phrase`, `generate_key`): only when the
   card holds **no** seed. Hidden once a seed is present (the module refuses to overwrite).
5. **Seed-present ops** (`verify_phrase`, `remove_key`): only when the card holds a seed.
6. **Credential + metadata** (`change_pin`, `change_puk`, pairing mgmt, name/NDEF/data):
   any usable card (has PIN, not locked).
7. **Factory reset**: any initialized card (and capable), and it is the escape from a
   locked/frozen card.

## Actions dropped by the "our module only" filter

Status flows with no `keycard_module` equivalent are not shown: `Login`, `Sign`,
`ExportPublicKey`/`ExportExtendedPublicKey` (these are the wallet/accounts flow, handled in
the main view, not administration), `Unblock with recovery phrase` (we expose only PUK
unblock), and the Status "move/add key pair to Status wallet" flows (Status-wallet
specific).
