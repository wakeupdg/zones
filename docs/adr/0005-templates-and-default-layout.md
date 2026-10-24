# Templates: Columns, Rows, Grid, Priority Grid, Focus; default is Priority Grid

Columns and Rows offer 2 to 5 zones; Grid offers 2x2 and 3x3; Priority Grid is 3 zones with a wide center; Focus is one center zone at 60 percent. A display with no assignment uses Priority Grid, matching the FancyZones default users expect.

## Amendment 2026-10-24 (LOCKED-SPEC challenge C1)

Focus is a one-leaf tree with surround 0.2 per side (ADR-0003 as amended): its single Zone is Zone Number 1 and resolves to the centered 60 percent of the visible frame; a modifier drop anywhere inside that Display's visible frame lands in it through the nearest-Zone rule (ADR-0009 as amended). Priority Grid is three side-by-side Zones at 25/50/25. Template names are the CONTEXT.md glossary names; built-in identifiers are derived from Template name and count at load and never persisted.
