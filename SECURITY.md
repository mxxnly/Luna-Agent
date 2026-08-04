# Security Policy

## Supported versions

- **Beta** (`0.x.y`): best-effort fixes on the latest Pre-release.
- **Stable** (`1.x.y` and newer): security fixes target the latest stable release on `main` / Latest GitHub Release.

## Reporting a vulnerability

Report security issues **privately** (GitHub Security Advisory on [mxxnly/Luna-Agent](https://github.com/mxxnly/Luna-Agent), or a private channel to the maintainer **mxxnly**).

Include:

- Affected agent version / commit
- Reproduction steps
- Impact (auth bypass, secret disclosure, remote command abuse, etc.)

**Do not** attach:

- Production WireGuard private keys or PresharedKeys
- Live `device_token` values
- Valid enroll codes for production tenants

## Hard rules in this project

- Secrets never appear in logs, UI, crash reports, or heartbeat payloads
- Control plane traffic is HTTPS-only with certificate validation
- Remote commands are signed and time-limited; replay is rejected
- WireGuard config files on disk use restrictive permissions (`0600`)
- Root helper authenticates peers by Unix socket credentials (UID)
