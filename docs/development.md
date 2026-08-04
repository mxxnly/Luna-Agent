# Development

## Prerequisites

- macOS with Xcode Command Line Tools (or Xcode)
- Go 1.22+
- Swift 5.9+ (`swift build`)
- Optional: `gh` for publishing releases

## Clone and build

```bash
git clone https://github.com/mxxnly/Luna-Agent.git
cd Luna-Agent
make ci
make build-app      # menu bar .app under dist/
VERSION=0.0.1 make installer
```

## Layout

```text
api/           Control API OpenAPI
branding/      Icons and marks
cmd/agent      lunaagentd
cmd/wghelper   luna-wghelper
cmd/mockcontrol
docs/          Documentation (you are here)
internal/      Go packages
macos/MenuBar  SwiftPM menu bar
packaging/     Embedded/legacy plists, Desktop doc templates
scripts/       build_installer, publish-github-release, …
```

## Useful targets

| Target | Purpose |
|--------|---------|
| `make ci` | lint + test + universal Go binaries |
| `make e2e` | mockcontrol enroll/heartbeat (dry-run WG) |
| `make installer` | dual pkgs → Desktop version folder |
| `make publish-release` | GitHub Release from Desktop folder |
| `make sign` / `make notarize` | optional Developer ID flow |

## Tests

```bash
LUNA_TEST_MODE=1 LUNA_WG_DRY_RUN=1 go test ./... -count=1
```

Do not commit secrets. See [CONTRIBUTING.md](../CONTRIBUTING.md) and [security.md](security.md).
