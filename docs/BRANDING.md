# Shogun branding — SHO-29

The approved chrome wordmark uses the conventional chrome S from the user-supplied image. The separate square chrome segmented S remains the iOS app icon.

- `ShogunWordmark.imageset` contains the approved full wordmark artwork. The shared `ShogunWordmark` view presents its center band without changing the source pixels, preserving the supplied chrome artwork and transparency in both appearances.
- `AppIcon.appiconset/AppIconLight.png` is the opaque 1024 × 1024 platinum-background default/light icon. `AppIcon.png` is the existing charcoal-background dark variant. Both share the chrome segmented S; iOS Home Screen appearance settings select the variant.
- Authentication and Library use the shared image component; the Library wordmark is centered. Both use it with a VoiceOver Shogun label. Authentication uses a compact fallback on narrow layouts.
- Authentication primary actions use a silver gradient with dark labels in dark mode and solid gunmetal with platinum labels in light mode. Steel blue is the interaction accent, with silver/steel ratings. Semantic success, warning and error colors have light and dark variants.

Artwork was approved in the SHO-29 chat. Original previews remain outside the asset catalog; the app bundles only its selected wordmark and icon.

The approved guide palette is implemented in semantic asset colors: Obsidian #111418, Gunmetal #1C2229, Graphite #29313A, Platinum #F3F5F7, Silver #D8DDE3, and appearance-specific steel blue accents. Shared surfaces, navigation, rows, fields, text, ratings and feedback use these tokens.

## Approved semantic mapping

| Role | Light | Dark |
| --- | --- | --- |
| Canvas | #F3F5F7 | #111418 |
| Surface | #FFFFFF | #1C2229 |
| Raised/input | #E6EAF0 | #29313A |
| Boundary | #B5BFCB | #46515E |
| Text | #182029 | #F3F5F7 |
| Secondary text | #526170 | #B3BDC8 |
| Interaction | #315E78 | #94C5E4 |
| Success | #246544 | #87C9A5 |
| Warning | #77520E | #E4BD7A |
| Error | #A02F3B | #F0A0A0 |

Procedural poster fallbacks use dark gunmetal and steel asset colors with platinum text; provider poster artwork retains its original colors. Native destructive actions retain their system role, while inline errors use the semantic error token.

## Profile and library navigation

Profile uses a compact account header and previews up to three libraries, with the saved default first. Tapping a preview opens that library in the Library tab, resets its navigation and search, and leaves the saved default unchanged. Manage opens the full library/default selector and creation controls; only writable libraries can be defaults. About & credits contains the version and TMDB attribution.
