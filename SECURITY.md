# Security Policy

## Supported versions

Security fixes target the latest released agent build on the default branch.

## Reporting a vulnerability

Please report security issues **privately** (GitHub Security Advisory on this repository, or a private channel to the maintainers).

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
