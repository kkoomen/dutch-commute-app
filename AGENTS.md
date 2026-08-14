# AGENTS.md — Dutch Commute Widget

## Project context

Dutch Commute Widget is a native iOS app (Swift / SwiftUI / WidgetKit) that answers one
question at a glance from the Lock Screen: **"Does my train run, and is it
delayed?"**

The user configures their daily journey — origin, destination, weekdays, and an
approximate departure time. A Lock Screen widget then shows the next matching
train with its live status, e.g.:

```
🚆 IC 1234
Utrecht → Amsterdam
18:42 · On time
```

Live data comes from the official NS Reisinformatie API. No scraping, no
unofficial sources.

## Project goal

- Lock Screen widget shows the user's relevant upcoming train: route, departure
  time, train information, and status (on time / delayed +N min / cancelled).
- Minimal configuration: origin, destination, days, approximate departure time.
- Correct live status from the official NS API.
- Simple, focused, maintainable codebase.

## Non-goals

- No maps, ticketing, push notifications, or complex trip planning UI.
- No scraping of NS websites or apps.
- No over-engineering: keep networking, models, app state, persistence, and
  widget code small and clearly separated.

## Behavior

- User configures a journey: origin, destination, weekdays, approximate
  departure time.
- The app finds the relevant upcoming train; the widget shows route, departure
  time, train information, and status.
- Status: on time / delayed (+N min) / cancelled — derived by pure functions
  (`status(of:)`, `selectRelevantTrip(config:trips:)`), checked in that order:
  cancelled wins over delays.
- Widgets degrade gracefully: no network → last known status or "unavailable",
  never stale data presented as fresh, never crash.
- Full rules and edge cases: `docs/behavior.md`.

## Architecture

- Two targets: the app (`DutchCommuteWidget`) and a widget extension
  (`DutchCommuteWidgetWidget`).
- Layers: networking (`NSAPIClient`), models (Codable DTOs + small domain
  models), app state + persistence (App Group shared container), widget
  (TimelineProvider).
- Journey configuration lives in the shared container so both the app and the
  widget can read it.
- Status derivation and journey selection are pure functions, unit-testable
  without network access.
- Full detail: `docs/architecture.md`.

## API & NS_API_KEY

- Official NS Reisinformatie API v3, trips operation (`/v3/trips`) — the
  only endpoint used; see `docs/api.md` and `docs/trips-api.html`.
- API key is read from the `NS_API_KEY` environment variable, supplied via
  the git-ignored `src/.env` file (bundled into the app as a resource, read
  at runtime by `APIKey.ns`). **Never expose, hard-code, or commit the API key.**
- Unit tests use bundled JSON fixtures; never use real API credentials or hit
  the live API in tests.
- Full detail: `docs/api.md`, `docs/development.md`.

## Development conventions

- Follow current Swift and Apple platform practices (modern Swift concurrency,
  SwiftUI, WidgetKit).
- Keep code readable and small; one clear responsibility per file.
- No dependencies without a clear reason — Foundation, SwiftUI, and WidgetKit
  should suffice. Dependencies require approval.
- Update `docs/` in the same change whenever behavior or architecture changes.
- Prefer simple solutions; avoid unnecessary features or over-engineering.

## Testing expectations

- Unit tests for: API decoding (fixtures), status mapping (on time / delayed /
  cancelled), journey selection, and edge cases (no trains, last train of day,
  crossing midnight, missing fields, nulls).
- Tests are deterministic: mocked API responses and injected clocks, no real
  network.
- Never claim tests passed without running them. Run the full test suite
  before finishing work; report results and any limitations.
- Full detail: `docs/testing.md`.

## Working style: safe, incremental

- Work in small steps: inspect → plan → implement → test → verify, one slice
  at a time.
- One logical change per step; keep diffs small and reviewable.
- Preserve existing user changes; never reformat or refactor unrelated code.
- Verify each step (build + relevant tests) before moving on.
- Report uncertainty instead of guessing. Stop and ask when scope or
  architecture would change, or when something is destructive.

## Graphify (knowledge graph)

This project uses **graphify** (installed skill: `SKILL.md` under the agent
skills directory, e.g. `/Users/koomen/.agents/skills/graphify/SKILL.md`) to
keep a queryable knowledge graph of the codebase in `graphify-out/`.

- **Codebase questions are graph queries first.** If `graphify-out/graph.json`
  exists, run `graphify query "<question>"` before reading files by hand.
- If no graph exists, build it with the graphify pipeline (`graphify <path>`
  or the `/graphify` skill). Structural (AST) extraction is free; semantic
  extraction of docs uses the host agent.
- After architecture-affecting changes, refresh the graph:
  `graphify <path> --update` (or `--watch` during active development).
- `graphify-out/` is generated output and git-ignored; never commit it.

## Subagents: roles, permissions, limitations

| Agent | File | Role | May | Must not |
|-------|------|------|-----|----------|
| Orchestrator | `.pi/agents/orchestrator.md` | Coordinate work, delegate, verify | Inspect repo, split work, delegate, run tests, review diffs, resolve conflicts, small fixes when delegation is not useful | Make broad code changes |
| Investigator | `.pi/agents/investigator.md` | Inspect and recommend | Read files, search code, inspect git history, propose approaches | Implement |
| Implementer | `.pi/agents/implementer.md` | Implement assigned changes | Edit files within assigned scope, run build/tests, update docs its change affects | Redesign unrelated areas |
| Tester | `.pi/agents/tester.md` | Test and improve coverage | Add/modify tests and fixtures, run suites, report bugs | Change production behavior unless requested |
| Reviewer | `.pi/agents/reviewer.md` | Review changes | Inspect diffs, run tests, report findings | Silently modify code |

- Agents may inspect any file relevant to their task.
- Agents may modify only files within their assigned scope.
- Agents must not delegate further unless explicitly allowed by the
  orchestrator.

## Orchestrator workflow

1. Understand the request — restate it if ambiguous.
2. Inspect the repository — current state, relevant docs, recent changes.
3. Split work into small tasks.
4. Delegate only when useful — do not delegate trivial work.
5. Collect and verify subagent results.
6. Resolve conflicts.
7. Run relevant tests.
8. Review the final diff.
9. Report changes, tests, risks, and remaining issues.

## Universal rules for all agents

1. Never expose, hard-code, or commit `NS_API_KEY` or any other secret.
2. Never use real API credentials in tests; never hit the live NS API in tests.
3. Never scrape NS websites or apps — official API only.
4. Never add dependencies without approval.
5. Never rewrite unrelated code; keep changes small and explain them.
6. Never delete files, reset changes, or perform destructive actions without
   explicit approval.
7. Never change project scope or architecture without orchestrator approval.
8. Never claim tests passed without running them.
9. Never hide failing tests, errors, or limitations — report honestly.
10. Preserve existing user changes.
11. Follow the project's architecture and conventions; update docs when
    behavior or architecture changes.
12. Report uncertainty instead of guessing.
13. Use the graphify knowledge graph for codebase questions (see
    "Graphify" section); keep it updated after architecture-affecting
    changes.
