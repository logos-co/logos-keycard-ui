# logos-keycard-ui

`keycard_ui` is the Keycard's app for Logos. It shows the cards in the smart-card readers, what
each tells before its PIN, and the accounts offered to Logos apps. It offers more from the card,
opened with its PIN: an EVM account, and native segwit and taproot ones. It also pairs a 3.x card
once, changes the PIN, and unblocks it with the PUK.

Every call goes to [`keycard_module`](https://github.com/logos-co/logos-keycard-module), which keeps
public material only, plus a 3.x card's pairing. The PIN, PUK and pairing password pass through this
app and the module to the card, and neither keeps them.

A Keycard has no screen. When it signs, the person relies on what the signer app shows, so the app
says so.

A 4.0 card whose identity Keycard didn't sign is refused. The app says why, shows the card's identity
key, and warns that a counterfeit could keep the PIN or the keys. The person may trust that one card
once they confirm they loaded the applet onto it themselves, and stop trusting it later.

```sh
nix build .#lgx
```

The end-to-end doctest (`doctests/keycard-ui-e2e.test.yaml`) runs the app in Basecamp's standalone
mode against the Keycard applet itself, in jCardSim. It offers accounts with the PIN after a wrong
one, then takes one back. It then swaps in a card another CA signed, trusts it, offers its EVM
account, and stops trusting it.

Licensed under MIT or Apache-2.0.
