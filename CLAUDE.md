# CLAUDE.md — V2rayN Sentinel

Guidance for AI coding assistants working in this repository.

## Nature of the app

V2rayN Sentinel is a **read-only, offline** macOS menu-bar tool: it tails v2rayN's
log files and raises tiered alerts. It never writes to v2rayN's files, never
controls processes, and never uses the network. Any change must preserve this
passive, read-only, offline behavior.

## Development environment: live proxy — avoid network bursts

This project is developed on a Mac where v2rayN runs in **sing-box TUN mode**,
which routes **all** outbound traffic — including an assistant's own API calls,
web fetches, and git operations — through a single live proxy connection. Bursty
or concurrent network activity can drop that connection. Therefore, when working
in this repository:

- **Do not launch background workflows or fan out concurrent subagents.** Work
  inline and single-threaded.
- **Do not run network commands** (WebSearch/WebFetch, curl/wget,
  git fetch/pull/push, dependency downloads) without explicit per-action
  approval — one at a time, and say so first.
- Prefer local-only operations. If the network is genuinely required, stop and ask.

## Commits

Commit under the repository owner's name only. Do **not** add a
`Co-Authored-By` trailer.

## Build & test

- `swift build` / `swift test` — offline, no external dependencies (49 tests).
- `./scripts/make-app.sh` packages `build/V2rayN Sentinel.app`.
