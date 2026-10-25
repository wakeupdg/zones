# Zones design

All Zones design lives on **one Figma page**: [Zones — Design board](https://www.figma.com/design/c1pMnDAGUn6jiXCu9yQp1I?node-id=11-2) (file "Zones — Logo Directions", key `c1pMnDAGUn6jiXCu9yQp1I`, page `11:2`). The file is private.

## Rule for new design work
1. Put new work on the same page, in a **new numbered Section below the last one** ("4 — …", "5 — …").
2. Add the new Section to "0 — Index".
3. Move (do not copy) boards that belong on the page, so each board exists once and linked instances stay linked.
4. Do not make new pages for Zones design.
5. Do not make new Figma files of any kind: no new design files, FigJam boards, Slides or Make files. Every change goes into the file above.
6. Every design agent brief must include rules 1–5.

## Sections (2026-10-24, updated 10:27 PM PT)
| Section | Node | Contents |
|---|---|---|
| 0 — Index | `28:807` | List of sections and the rule above |
| 1 — Color matrix | `28:808` | 9 shapes (Sash row `45:1499` added) × 7 palettes (Coal Fern, Ember Pine added) = 63 cells; light/dark icons, 32 px icon, menu-bar strip per cell; originals outlined; ⚠ marks cells below 3:1 |
| 2 — Directions | `28:809` | Full boards: Tessera, Dash, Zed, Veil, Flush |
| 3 — Veil × Tessera forks | `28:810` | Facet, Span, Lift |
| 4 — Sash (Span × Facet) | `35:1147` | Sash app icon (light `35:1150`, dark `35:1160`), hinted 128/32/16, menu-bar glyph direction B (g18 `36:1220`, b18 `36:1231`), lockups, 1x proof `36:1327`, contrast table |
| 5 — Palettes | `46:1725` | Coal Fern and Ember Pine swatch cards with contrast tables |
| 6 — Final app icon | `50:1597` | Chosen icon: masters (light `50:1607`, dark `50:1618`), Icon Composer flat layers, hinted 128/32/16, simulated modes, 1x proof, rationale |

## Palettes
| Palette | Colors |
|---|---|
| Tessera | `#1C1F24` `#F4F2EE` `#FF6A2B` |
| Dash | `#0B1220` `#C8F169` `#EEF2F4` |
| Zed | `#0E3B2E` `#1F9D6E` `#7CE3B6` `#F6F3EA` |
| Veil | `#0A0F1C` `#5CE1E6` `#0E8FA3` `#EAF0F7` |
| Flush | `#24272D` `#C9CED6` `#F5F6F8` `#E3A83F` |
| Coal Fern | `#1C1F24` `#F4F2EE` accent L `#178A5F` accent D `#5FD3A0` |
| Ember Pine | `#0E3B2E` `#F6F3EA` accent L `#C2410C` accent D `#FF7A3D` |

## Decision (2026-10-24, 10:46 PM PT)
- **App icon: Sash × Coal Fern, refinement B "Glass tiles" with lit-zone treatment 2 "Active zone".** Chosen by the user from inline mocks.
  - Layout = menu-bar glyph B: one tall lit zone on the left, two stacked zones on the right. No seam notches.
  - Lit zone: accent border (about 33 px at 1024) with a soft accent fill (28 %), like the zone highlight during a drag.
  - The two right zones are Liquid Glass tiles. A soft accent glow sits behind the tiles.
  - Colors: Coal Fern (light body `#F4F2EE`, dark body `#1C1F24`, accent L `#178A5F`, accent D `#5FD3A0`).
  - Delivery: an Icon Composer `.icon` file (flat layers; macOS 26 adds the glass and the Default, Dark, Clear and Tinted modes).
- Menu-bar glyph: direction B as built (g18 `36:1220`, b18 `36:1231`). No change.

## Earlier open decisions (closed by the decision above)
- No direction was chosen before 10:46 PM PT. User picks: Tessera (directions), Lift (forks), menu-bar glyph direction B. Design agent top 3 new cells: Sash × Coal Fern, Sash × Ember Pine, Tessera × Ember Pine.
- New cells below 3:1: Flush × Coal Fern (D 1.56), Flush × Ember Pine (L 2.48, D 2.15), Span × Coal Fern (L 2.70), Span × Ember Pine (L 1.72). No Sash cell is flagged.
- Sash weak spot: cream glass edge over accent D (1.66 Coal Fern, 2.34 Ember Pine). 16 px Sash icons are muddy at 1x.
- Contrast below 3:1 on light icons: Dash × Veil, Zed × Veil, Flush × Veil, Span × Zed.
- Pure orange `#FF6A2B` on cream `#F4F2EE` is only 2.56:1; forks Facet and Lift add a charcoal keyline.
