# ADR-S: App icon — the real Keycard logo, full-bleed

- Status: Accepted
- Date: 2026-11-15
- Scope: `keycard_ui` (the launcher-tile artwork; `src/icons/keycard.png`)
- Issue: #2

## Context

The app's launcher tile was a navy rounded square with a generic smart-card graphic (chip + NFC
waves). It did not carry the Keycard brand, and the rounded corners were baked into the PNG even though
Basecamp rounds the tile itself.

## Decision

Use the **real Keycard logo** — the key / "k" glyph — as the icon:

- Sourced from keycard.tech at native resolution (`logo_256_256.png`, actually 400×400) and
  **downscaled** to the 256×256 tile; the small copies embedded in repos (28px / 180px) would be soft,
  so they were not used.
- A **full black 256×256 square, not rounded** — Basecamp rounds the tile at display time, so a
  pre-rounded PNG double-rounds.
- The glyph is **centred with margin** (height ≈ 64% of the tile, ~46px top/bottom), matching the inset
  the old tile's graphic had, rather than running edge to edge.

## Consequences

- The app reads as Keycard at a glance, consistent with the physical device and the wider Keycard
  ecosystem.
- The launcher tile can be **cached** by Basecamp; a running instance may keep the old tile until the
  module is reinstalled, even after a restart.
- The reusable rules for Basecamp icon artwork were captured as the `basecamp-app-icon-design` skill in
  the shared basecamp-skills set.

## Alternatives considered

1. **Recolour the existing card graphic.** Rejected: it is not the brand mark.
2. **Upscale the 180px logo already in keycard-basecamp.** Rejected: soft; the real 400px asset
   downscales cleanly.
3. **Bake rounded corners / a gradient (as some module icons do).** Rejected: Basecamp rounds the tile
   itself, and the Keycard brand is a white mark on black.
