# LunaAgent branding

## Name
**LunaAgent** — macOS agent (WireGuard + device telemetry + remote control API).

## Palette
| Token | Hex | Use |
|-------|-----|-----|
| `midnight` | `#0B1220` | App icon ground, dark UI |
| `moon` | `#E8EEF7` | Crescent / mark on dark |
| `ink` | `#0B1220` | Mark / wordmark on light |
| `paper` | `#FFFFFF` | Light backgrounds |

Avoid purple gradients and glow. Flat lunar navy + silver.

## Asset map (where to use)

| Path | Use |
|------|-----|
| `app-icon/AppIcon-*.png` | Xcode Asset Catalog / `.icns` source |
| `menubar/MenuBarTemplate-*.png` | Menu bar status item (`isTemplate = true`; may need manual cleanup to pure alpha template) |
| `mark/mark-on-dark.png` | Splash, about, dark marketing |
| `mark/mark-on-light.png` | Docs, light UI, panel |
| `wordmark/*` | README, website, installer header |
| `panel/*` | Control panel favicon / PWA icons |
| `social/*` | GitHub / OG previews |

## Notes
- Generated masters may need a designer pass before App Store / final notarized release.
- Menu bar icons on macOS work best as **template images** (black + transparent). Convert in Preview/Sketch if the PNG still has a white plate.
