# ADR 0002: Build and test pipeline

## Status

Accepted (amended: no GitHub Actions in this repo)

## Context

Builds and tests must be reproducible via Makefile. Automated GitHub Actions were removed from Luna-Agent — CI for the product lives primarily around the control panel deploy; agent quality is gated locally with `make ci` / `make e2e` before release.

## Decision

### Local (Makefile)

Canonical targets: `lint`, `test`, `test-race`, `build`, `build-app`, `integration`, `e2e`, `package`, `sign`, `notarize`, `ci`, `release-smoke`.

`make ci` = lint + test + build + integration.

### CI / release

- No `.github/workflows` in this repository.
- Sign / notarize / GitHub Release are manual (`make package`, `make sign`, `make notarize`) when certificates are available.

### Test pyramid

1. **Unit** — crypto, wg FSM, api marshal, metrics sanitize, log redaction.
2. **Integration** — agent against `mockcontrol`.
3. **E2E** — `make e2e` (dry-run WG).
4. **Release smoke** — `make release-smoke` on a clean Mac profile.

### Versioning

Embed version via `-ldflags "-X github.com/mxxnly/Luna-Agent/internal/version.Version=…"`.

## Consequences

- Contributors run `make ci` locally before merge.
- Panel auto-deploy remains in `vpn-control-panel` only.
