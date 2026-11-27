# Keycard app: how it behaves

One section per behaviour. Each says what the app does and why, in the words the code follows.

## Two areas: Wallets and Card administration

The app has two tabs. **Wallets** lists the Keycard wallets saved on this computer and their accounts.
**Card administration** manages the card in a reader: set it up, its PIN and PUK, its recovery keys,
its name, pairing, factory reset. Administration is a tab, not a modal, so a card's state and its
actions are in view together.

## Card administration

With one card in a reader it is selected at once; a picker appears only with two or more. With none,
an empty state says "No Keycard to administer" with a link to get a reader (a Shell signs, but its
card has to move into a reader to be administered).

**Details** shows the on-card name as the title ("Keycard" when it has none), then the card
fingerprint, key id, applet version, whether private keys are present, and authenticity, checked
automatically with no PIN ("Verified by Keycard", "Not certified by Keycard", "Could not verify").
**More details** (initialized, paired cards) shows PIN and PUK attempts left and, on 3.x, pairing
slots. Card details and authenticity are information, not actions: they need no PIN and answer in a
small read-only dialog.

### Which actions a card offers

Mirrors the Status desktop Keycard management UI, reduced to what `keycard_module` exposes:

| Card state | Actions |
|---|---|
| Not set up (no PIN) | Set up card |
| 3.x, not paired | Pair this app; Factory reset |
| PUK used up | Factory reset only |
| PIN blocked | Unblock PIN; Factory reset |
| No seed | Create recovery phrase; Import recovery phrase; Generate keys without backup |
| Seed present | Check recovery phrase; Erase keys |
| Any usable card | Change PIN; Change PUK; Update name; and, under **Advanced** (collapsed): change pairing password, remove a pairing slot (3.x), NFC text, read and write card data |

Destructive actions (Erase keys, Factory reset) are red and need a typed confirmation. The list waits
behind "Reading card…" until the card's state is known, so the wrong set never shows first.

### Blocked state and re-reading the card

Whether a card is blocked comes from the no-PIN `status` read (`pinRetries`, `pukRetries`), not from
`cards()`, whose `pinRetries` can be stale and which has no `pukRetries`. The panel reads it when a
card is selected, and again after **every** card operation, done or refused, so a successful Unblock
PIN clears the blocked state and a PIN blocked by wrong entries shows at once.

### Guided operations (`CardFlow`)

Every operation runs as a guided flow: a title line (the operation, and the card's name and Wallet
ID), "Step N of M", one input per screen, then working, success or error. PINs and PUKs are entered
as circles (`PinDots`): digits only, fixed length, masked and not selectable, so they can't be
copied. Recovery phrases use a word grid; a generated phrase is shown for backup, confirmed with
three of its words, then loaded with the PIN already entered.

- The flow branches on the reply's `code`, never its wording. `WrongSecret` is a wrong PIN, PUK or
  pairing password: the flow returns to that step and shows the attempts left, read from the card.
  A blocked PIN or PUK has no code of its own yet (it comes back as `Unavailable`), so the flow reads
  the card's attempts and 0 means blocked; any other `Unavailable` is shown as the error it is.
- On Create, a wrong PIN while loading the phrase already shown retries loading that phrase.
- On a Keycard 4.0, the PUK's first six digits become a second (alternate) PIN, so setting up a card
  refuses a PUK that starts with the chosen PIN, at the PUK step.
- Changing the PIN refuses a new PIN equal to the current one; weak PINs (000000, 123456, …) get a
  warning.
