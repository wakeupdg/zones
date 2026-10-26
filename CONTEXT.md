# Zones

Zones is a macOS window manager that lets a person define rectangular regions on each display and snap windows into them by dragging with a modifier or by keyboard.

## Language

### Layout

**Layout**:
A named arrangement of Zones that tiles one display with no gaps and no overlaps.
_Avoid_: grid, scheme, preset

**Zone**:
One rectangular region of a Layout into which a window can be snapped.
_Avoid_: cell, slot, region

**Zone Number**:
The ordinal of a Zone within its Layout, counted row by row from the top-left.
_Avoid_: index, id

**Template**:
A built-in Layout family (Columns, Rows, Grid, Priority Grid, Focus) that generates a Layout for a chosen zone count.
_Avoid_: preset, default layout

**Margin**:
The space between the edge of the display and the outer Zones.
_Avoid_: padding, inset

**Gap**:
The space between two neighboring Zones.
_Avoid_: spacing, gutter

### Placement

**Assignment**:
The link from a Display (and, when supported, a Space) to the Layout active there.
_Avoid_: mapping, binding

**Display**:
One physical or virtual screen attached to the Mac, identified stably across reconnects.
_Avoid_: monitor, screen

**Space**:
One macOS virtual desktop on a Display.
_Avoid_: desktop, workspace

**Snap**:
Moving and resizing a window so that it fills a Zone.
_Avoid_: dock, tile, attach

**Span**:
A Snap into the union of two or more Zones chosen during one drag.
_Avoid_: merge-snap, multi-zone

**Original Frame**:
The size and position a window had before its first Snap.
_Avoid_: previous size, saved frame

**Restore**:
Returning a window to its Original Frame.
_Avoid_: unsnap, reset

### Interaction

**Drag Session**:
The period from a mouse-down on a window title bar until the mouse-up that ends the move.
_Avoid_: drag, move gesture

**Activation Modifier**:
The key held during a Drag Session to show the Overlay and arm the Snap.
_Avoid_: trigger key, shift key

**Span Modifier**:
The key held during an armed Drag Session to accumulate Zones into a Span.
_Avoid_: multi key, control key

**Overlay**:
The translucent picture of the active Layout drawn over a Display during an armed Drag Session.
_Avoid_: preview, HUD

**Exclusion**:
A rule that keeps Zones from ever snapping windows of a given app.
_Avoid_: blacklist, ignore list
