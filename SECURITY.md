# Security Policy

## Supported versions

| Line | Policy |
|------|--------|
| **Beta** (`0.x.y`) | Best-effort fixes on the latest Pre-release |
| **Stable** (`1.x` and newer) | Security fixes target the latest stable release on `main` / Latest GitHub Release |

## Reporting a vulnerability

Report **privately** via a [GitHub Security Advisory](https://github.com/mxxnly/Luna-Agent/security/advisories/new) on `mxxnly/Luna-Agent`, or a private channel to the maintainer **mxxnly**.

Include:

- Affected agent version or commit
- Clear reproduction steps
- Impact assessment (auth bypass, secret disclosure, remote command abuse, …)

**Do not** attach:

- Production WireGuard private keys or PresharedKeys
- Live `device_token` values
- Valid enroll codes for production tenants

## Project hard rules

- Secrets never appear in logs, UI, crash reports, or heartbeat payloads
- Control-plane traffic is HTTPS-only with certificate validation
- Remote commands are signed and time-limited; replays are rejected
- WireGuard config files on disk use mode `0600`
- The root helper authenticates peers by Unix socket credentials (UID)

Operational detail: [docs/security.md](docs/security.md).
