# Keycard Shell re-prompts the "Connect wallet" consent for every exported public key

**Context:** found while dogfooding the Keycard Shell through the Logos Basecamp Keycard module
(the host that drives the Shell over USB: https://github.com/logos-co/logos-keycard-shell-module ,
with the account UI in https://github.com/logos-co/logos-keycard-ui ). The consent screen itself is
firmware; the re-prompt may be driven by the host re-initiating the session per key, so if this is
host-side rather than firmware, happy to move it to `keycard-tech/shelljs` or the Logos module
above, whichever you point me to.

**TL;DR:** When a host exports several public keys in one go (e.g. previewing accounts 0..N
to add a wallet), the Shell shows its "Connect wallet / asking to export public keys" consent
screen **once per key** and waits for an OK each time, instead of granting consent once for the
connection. Confirming four separate times was needed to list the accounts. The consent wording
("export public **keys**", "a wallet you want to use your Shell with") reads as a per-connection
authorization, so re-prompting per key looks wrong and is a poor flow.

## Environment
- Device: Keycard Shell, USB `1209:21f7` ("Status Research & Development / Keycard Shell"),
  latest firmware, unlocked.
- Host: a desktop app driving the Shell over USB HID to export extended public keys for a range
  of derivation paths in a single request (the app sends one batched export of ~5 paths:
  `m/44'/60'/0'/0/0 … /0/4`).
- Platform: Linux (not relevant to the behavior; the consent loop is on the device).

## Steps to reproduce
1. In the host, choose "add accounts / show accounts" so it requests a page of public keys
   (several derivation indexes in one export request).
2. The Shell shows: **"Connect wallet — The connected USB device is asking to export public
   keys. Only click OK if this [is] a wallet you want to use your Shell with."**
3. Press **OK** on the Shell. The screen clears briefly, then the **same** "Connect wallet"
   consent reappears.
4. Repeat. The accounts only appear in the host after pressing OK ~4 times (one per key in the
   batch).

(Video attached.)

## Expected
Per the consent's own wording and the usual hardware-wallet model, the "Connect wallet" consent
should be a **per-connection / per-session** authorization: confirm once, then export all the
requested public keys under that one OK (optionally re-prompt only on a new USB connection, a
different wallet/seed, or after a timeout). Deriving read-only public keys is not a signing
operation, so a per-key tap is unexpected.

## Actual
The "Connect wallet" consent is re-shown and re-awaited for **each** exported public key in a
single batched export, requiring N taps for N keys.

## Why it matters
- First-run onboarding (listing accounts to add) is the first thing a user does, and it makes the
  device feel stuck ("I pressed OK, why is it asking again?").
- The prompt says "export public keys" (plural) and frames a one-time trust decision, which the
  per-key re-prompt contradicts.

## Open question for the maintainers
Is the per-key consent intentional (each public-key read is a distinct authorization), or should
the first OK cover the connection/session? If intentional, the consent copy and the number of
taps should be made predictable (e.g. "Confirm N public-key requests"). If not, caching the
consent for the connection would fix it.

## Host-side note (for context, not asking you to fix)
On the host we have reduced the default preview to one key at a time for Shell connections, so the
common "add one account" flow is a single OK. This is a workaround; adding several accounts still
incurs one consent per key, which is why we're reporting the device behavior.
