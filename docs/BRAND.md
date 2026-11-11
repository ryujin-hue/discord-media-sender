# Brand mark

The product mark of Discord Media Sender is a geometric origami paper airplane: folded
wing planes, a centre spine and a violet nose tip. It reads as speed and lightweight
delivery without using any Discord brand asset. The mark contains no letterforms — the
wordmark is separate sans-serif type.

## Variants

All four variants live in `assets/brand/` and are the original source of truth.

| File | Use |
|---|---|
| `logo_paper_plane.svg` | Mark on the dark plate (circle). Used by `BrandPlate`. |
| `logo_paper_plane_mark.svg` | Mark only, transparent background. Used by `BrandMark` on dark surfaces and by the launcher foreground vector. |
| `logo_paper_plane_icon.svg` | Rounded tile, dark plate. Used as the launcher icon and on the launch screen. |
| `logo_paper_plane_light.svg` | Light background variant. Used by `BrandMark(light: true)`. |

In the application the mark is rendered from the SVG with `flutter_svg`, so it stays crisp
at every size and the fold proportions are never re-created by hand.

## Rules

- Clear space around the mark of at least 12 % of its width.
- The accent violet `#8B5CF6` / `#A78BFA` is used on the nose only.
- No shadows, no glows, no 3D extrusion.
- The icon tile is used in the About header and as the launcher icon.
- A vector recreation of the icon keeps the same fold proportions. The launcher foreground
  is `android/app/src/main/res/drawable/ic_launcher_foreground.xml`, generated from the same
  geometry and scaled for the 108 dp adaptive icon canvas with its 66 dp safe zone.

## Colours

| Role | Value |
|---|---|
| Dark plate | `#1C2030` |
| Paper | `#F8FAFC` |
| Fold | `#E2E8F0` |
| Spine | `#94A3B8` |
| Nose accent | `#8B5CF6` (icon tile: `#A78BFA`) |
| Crease | `#1E293B` |
| Soft crease | `#64748B` |

## Raster sizes

The launcher icons and the launch screen logo are rendered from the SVG with a headless
Chromium at the densities Android expects:

| Density | Launcher icon | Launch logo (96 dp) |
|---|---|---|
| mdpi | 48 px | 96 px |
| hdpi | 72 px | 144 px |
| xhdpi | 96 px | 192 px |
| xxhdpi | 144 px | 288 px |
| xxxhdpi | 192 px | 384 px |

The adaptive icon (API 26 and newer) uses the dark plate as the background and the vector
foreground, so it stays sharp on every screen.
