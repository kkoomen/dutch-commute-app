# Project Goal

## Problem

Commuters with a fixed daily train journey constantly ask one question:
**"Does my train run, and is it delayed?"** Answering it means opening an app,
searching a route, and reading through a list of departures. On a morning
commute, that takes too long.

## Solution

A simple native iOS app with a Lock Screen widget that answers the question at
a glance. The user configures their daily journey once; the widget shows the
next matching train and its live status:

```
🚆 IC 1234
Utrecht → Amsterdam
18:42 · On time
```

```
🚆 IC 1234
Utrecht → Amsterdam
18:42 · +8 min
```

```
🚆 IC 1234
Utrecht → Amsterdam
Cancelled
```

## Goals

- Lock Screen widget shows the user's relevant upcoming train: route,
  departure time, train information, and live status (on time / delayed / cancelled).
- Minimal configuration: origin, destination, days of the week, approximate
  departure time. No accounts, no profiles, no routing options.
- Correct live data from the official NS Reisinformatie API.
- Small, readable, maintainable codebase — this is a tool, not a platform.

## Success criteria

- A user can set up their journey in under a minute.
- The Lock Screen widget always shows a sensible answer: a train, a status,
  or a graceful "unavailable" state — never stale data presented as fresh.
- Delays and cancellations are reflected correctly for the user's specific
  train (not just any train on the route).

## Non-goals

- No maps, no ticketing, no seat booking, no notifications.
- No complex multi-day or multi-leg trip planning UI.
- No scraping of NS websites or apps.
- No web backend; the app talks to the NS API directly.

## Design principles

- **Simple over clever.** One question, one answer, minimal UI.
- **Deterministic core.** Status derivation and train selection are pure
  functions so they can be tested exhaustively.
- **Graceful degradation.** When the network or the API fails, the widget
  shows last known data or an unavailable state — it never crashes or lies.
