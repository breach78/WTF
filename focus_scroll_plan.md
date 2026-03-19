# Focus Mode Scroll Authority Plan

This plan mirrors the main-workspace vertical-scroll cleanup, but is scoped to focus mode only.

Scope:
- Focus mode only
- Vertical scroll ownership only
- No behavioral changes to main workspace

## Problem Statement

Focus mode currently combines multiple scroll and scroll-correction layers:

- card-level canvas scroll through `ScrollViewProxy`
- preserved-viewport boundary switching
- outer caret keep-visible
- typewriter-mode caret repositioning
- inner `NSTextView` scroll-origin normalization
- programmatic caret retry and fallback reveal

These layers are individually valid, but they do not share a single owner model.
As a result, one user action can trigger several delayed scroll decisions.

## Design Goal

Introduce explicit focus-mode vertical scroll ownership so that only one layer is authoritative at a time.

Initial owners:

- `canvasNavigation`
  - card activation, entry-centering, search reveal, ordinary card-to-card canvas movement
- `boundaryTransition`
  - temporary preserved-viewport state while switching cards at an arrow-key boundary
- `caretEnsure`
  - outer scroll driven by caret visibility or typewriter mode
- `fallbackReveal`
  - emergency reveal only when a boundary switch cannot attach the expected editor/responder

## Rules

1. Card-level canvas scrolling must explicitly claim `canvasNavigation`.
2. Boundary transitions must claim `boundaryTransition` before changing card state.
3. Caret keep-visible must claim `caretEnsure` before moving the outer scroll view.
4. Fallback reveal must claim `fallbackReveal` and only run if it is still the current owner.
5. Fallback reveal should not fire while live editor layout is still pending.
6. Late async callbacks must verify that their claimed owner is still current before they move the viewport.

## Expected Simplification

This does not remove all focus-mode complexity, but it removes the most harmful overlap:

- late fallback reveal overriding a newer caret scroll
- older card-navigation callbacks moving the canvas after caret ownership has taken over
- “who moved the viewport last?” being implicit

## Coordinate Authority Note

This first pass does not delete predicted or measured layout paths.
Instead, it narrows which owner is allowed to act while those coordinates are still settling.

The next structural step, if needed, would be:

- make live editor layout the only post-switch success authority
- reduce inner text-view normalization so it behaves like editor hygiene, not a second scroll engine

Current implementation status:

- scroll owners are split in code
- bulk focus-mode normalization burst is removed
- scroll-wheel-driven focus-mode normalization is disabled
- offset normalization now runs only as caret-owned hygiene or direct width-sync, not as a general late scroll correction layer
- boundary transitions now distinguish:
  - ordinary mid-viewport card switches
  - edge-reveal transitions that may need later minimal reveal
- fallback reveal is now armed only for true edge-reveal transitions, not every boundary switch
- post-switch caret retry and fallback reveal now wait for a fresh live editor layout commit before they start consuming retry budget
- switching to a different focus-mode card now explicitly marks that card as awaiting a fresh live editor layout commit
