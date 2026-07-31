# ADR 0002: Build and test pipeline

## Status

Accepted

## Context

Every change must land with a green build and tests. Releases require signed, notarized packages and a smoke checklist.

## Decision

### Local (Makefile)

Canonical targets: `lint`, `test`, `test-race`, `build`, `build-app`, `integration`, `e2e`, `package`, `sign`, `notarize`, `ci`, `release-smoke`.

`make ci` = lint + test + build + integration (same gate as GitHub Actions).

### CI

- `.github/workflows/ci.yml` on push/PR to `main` (macos runner).
- Fail on test/lint/build failure or secret deny-list hits in test logs.
- `.github/workflows/release.yml` on tags `v*`: package → sign → notarize → GitHub Release + SHA-256.

### Test pyramid

1. **Unit** — crypto, wg FSM, api marshal, metrics sanitize, log redaction.
2. **Integration** — agent against `mockcontrol` (enroll/heartbeat/commands).
3. **E2E** — scripted flows; WG dry-run in CI; real TUN on staging.
4. **Release smoke** — Gatekeeper, launchd, heartbeat on a clean Mac profile.

### Versioning

Embed version via `-ldflags "-X github.com/mxxnly/Luna-Agent/internal/version.Version=…"`.

## Consequences

- Placeholder packages must still compile and pass `make ci`.
- Release secrets live only in GitHub Environment `release`.
