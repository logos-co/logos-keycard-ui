# ADR-D: Per-action interaction in a modal over the inline panel

- Status: Accepted
- Date: 2026-11-13
- Scope: `keycard_ui` (UI only; no backend or `.rep` change)
- Issue: #2 (amends ADR-A's inline per-operation form)

## Context

ADR-A moved administration out of a modal into a top-level inline area, and kept the
per-operation form inline: selecting an action revealed its fields, submit button and
result below the action list, in the same scrolling column.

On real hardware this placement failed in practice:

- The action list for an initialized card is long (a dozen-plus operations). The form and,
  critically, the result line sat below it, off the bottom of the view.
- After running an operation, the result was written but not seen. The user's report was
  "actions do not show result".

## Problem

The inline form put the active operation and its outcome below a long list, so the one
thing the user needs after acting, the result, was the least visible thing on screen. The
panel also did not scroll, so lower actions and the form were unreachable at some sizes.

## Decision

Open the single-operation interaction in a centred modal dialog, and make the panel scroll.

1. Selecting an action opens a modal (`LogosDialog`, centred on the window overlay) that
   contains that action's fields, the disabled-reason hint, the submit button and the
   result. The result is therefore always in view, in a focused surface, for exactly the
   operation in progress.
2. The read-only info ops (ADR-C: Card details, Check authenticity) present their result
   in the same modal, with no form.
3. The modal cannot be dismissed while an operation is in flight, preserving the
   serialised, one-operation-at-a-time safety property ADR-A's modal had.
4. The Administration panel itself scrolls, so the full action list is reachable at any
   size.

This is a deliberate, scoped return to a modal for the single-operation interaction only.
The two top-level areas and the visible risk-grouped action list from ADR-A stay inline;
ADR-A moved administration as a whole out of a modal, and that still holds. What returns to
a modal is one action's form and result, for focus and result-visibility.

## Consequences

Positive:

- The result of every operation is visible, in context, without scrolling.
- One operation at a time, in a focused surface, with the mid-operation dismissal guard.
- The panel scrolls; long action lists are fully reachable.

Costs and risks:

- A modal is a layer over the panel. It must centre on the window, not the panel column,
  and cap its height and scroll its form so no field or button is clipped on small
  windows.
- This is an interim ("for now") per the request. If inline results are preferred later,
  the form can move back into the panel with the result pinned above the fold instead.

## Alternatives considered

1. Keep the form inline but pin the result above the fold / as a sticky bar. Lighter, but
   the active form still competes with a long action list for the same column. Considered;
   may revisit if the modal proves heavy.
2. Scroll the panel only, leaving the form inline at the bottom. Rejected: scrolling fixes
   reachability but not the "result is below everything" problem.
