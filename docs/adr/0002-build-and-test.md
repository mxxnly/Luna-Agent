# ADR 0002: Build and test pipeline

## Status

Accepted (amended: no GitHub Actions in this repo)

## Context

Builds and tests must be reproducible from a Makefile. GitHub Actions were removed from this repository — panel deploy CI lives with `vpn-control-panel`; agent quality is gated locally with `make ci` / `make e2e` before each release.

## Decision

### Local (Makefile)

Canonical targets: `lint`, `test`, `test-race`, `build`, `build-app`, `integration`, `e2e`, `installer`, `publish-release`, `package` (deprecated), `sign`, `notarize`, `ci`, `release-smoke`.

`make ci` = lint + test + build + integration.

### CI / release

- No `.github/workflows` required for packaging; releases are published with `make installer` then `make publish-release` (see [releasing.md](../releasing.md)).
- Sign / notarize remain optional when Developer ID certificates are available.

### Test pyramid

1. **Unit** — crypto, wg FSM, api marshal, metrics sanitize, log redaction.
2. **Integration** — agent against `mockcontrol`.
3. **E2E** — `make e2e` (dry-run WG).
4. **Release smoke** — `make release-smoke` on a clean Mac profile.

### Versioning

Embed version via `-ldflags "-X github.com/mxxnly/Luna-Agent/internal/version.Version=…"`.

Product versions: **`0.x.y` = beta** (GitHub Pre-release); **`1.0.0+` = stable**. Default installer version: `0.0.1`.

## Consequences

- Maintainers run `make ci` locally before merge.
- Panel auto-deploy remains in `vpn-control-panel` only.
