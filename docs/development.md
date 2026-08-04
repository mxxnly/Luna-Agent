# Development

## Prerequisites

- macOS with Xcode or Command Line Tools
- Go **1.22+**
- Swift **5.9+** (`swift build`)
- Optional: `gh` for publishing releases

## Quick start

```bash
git clone https://github.com/mxxnly/Luna-Agent.git
cd Luna-Agent
make ci
make build-app                 # menu bar .app under dist/
VERSION=0.0.1 make installer   # dual pkgs on the Desktop
```

## Repository layout

```text
api/              Control API OpenAPI
branding/         Icons and marks
cmd/agent         lunaagentd
cmd/wghelper      luna-wghelper
cmd/mockcontrol   local control plane for tests
docs/             product & maintainer documentation
internal/         Go packages (api, wg, metrics, …)
macos/MenuBar     SwiftPM menu bar app
packaging/        plists, legacy postinstall, Desktop doc templates
scripts/          installer, icon pipeline, publish-github-release
```

## Make targets

| Target | Purpose |
|--------|---------|
| `make ci` | Lint + tests + universal Go binaries |
| `make e2e` | Enroll / heartbeat against mockcontrol (WG dry-run) |
| `make installer` | Dual pkgs → `~/Desktop/LunaAgent/<VERSION>/` |
| `make publish-release` | GitHub Release from that Desktop folder |
| `make sign` / `make notarize` | Optional Developer ID flow |

## Tests

```bash
LUNA_TEST_MODE=1 LUNA_WG_DRY_RUN=1 go test ./... -count=1
```

Do not commit secrets. See [CONTRIBUTING.md](../CONTRIBUTING.md) and [security.md](security.md).
