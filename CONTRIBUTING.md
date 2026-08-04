# Contributing

## Maintainer

**mxxnly** owns this repository (see [LICENSE](LICENSE)). Attribution on commits and releases is human-only.

## Attribution

- Identify **human** authors on commits and pull requests.
- Do **not** add `Co-authored-by` trailers for AI coding tools.
- Do not add “generated with …” badges or all-contributors lists for tooling.

## Setup

1. Clone the repository.
2. Install Go 1.22+ and Xcode Command Line Tools (menu bar companion).
3. Read [docs/development.md](docs/development.md), [docs/architecture.md](docs/architecture.md), and [api/openapi.yaml](api/openapi.yaml).

## Workflow

1. Branch from `main` (`feature/…`, `fix/…`, `docs/…`).
2. Prefer conventional commits:
   - `feat:` — user-facing capability
   - `fix:` — bug fix
   - `docs:` — documentation only
   - `chore:` — tooling, packaging, branding
   - `security:` — auth, crypto, secret handling
3. Open a pull request against `main` with **what** and **why**.
4. Run `make ci` locally before requesting review.

## Code guidelines

- Never log or print WireGuard private keys, PSK, enroll codes, or device tokens.
- Keep `internal/` packages small and bounded (`api`, `wg`, `metrics`, `secure`, …).
- The menu bar must not expose secrets; Device ID is fine to copy.
- New Control API fields require an OpenAPI update in the same PR.

## Testing

- Unit-test config validation and command signature verification.
- When touching VPN: manual up / down / apply conf / rollback / revoke before merge.
- Before a release build: `VERSION=x.y.z make installer` — see [docs/releasing.md](docs/releasing.md).
