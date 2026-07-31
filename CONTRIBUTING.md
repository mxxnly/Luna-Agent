# Contributing

## Development setup

1. Clone this repository.
2. Install a recent Go toolchain and Xcode (menu bar companion).
3. Read [docs/architecture.md](docs/architecture.md) and [api/openapi.yaml](api/openapi.yaml).

## Workflow

1. Create a branch from `main` (`feature/…`, `fix/…`, `docs/…`).
2. Keep commits focused; prefer conventional messages:
   - `feat:` new user-facing capability
   - `fix:` bug fix
   - `docs:` documentation only
   - `chore:` tooling, packaging, branding
   - `security:` auth, crypto, secret handling
3. Open a pull request against `main`.
4. Ensure the PR description states **what** and **why**; link issues when relevant.

## Code guidelines

- Do not log or print WireGuard private keys, PSK, enroll codes, or device tokens.
- Prefer small packages under `internal/` with clear boundaries (`api`, `wg`, `metrics`, `secure`).
- Menu bar UI must not expose secrets; Device ID is OK to copy.
- New Control API fields require an OpenAPI update in the same PR.

## Testing

- Unit-test config validation and command signature verification.
- Manual checklist before merge when touching VPN: up / down / apply conf / rollback / revoke.
