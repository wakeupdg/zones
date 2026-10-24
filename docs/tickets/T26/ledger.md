decision | panels(_:) keeps the contract signature (frame = layout.visibleFrame fallback); panels(_:topology:) is the overload with the full Display frame. The T31 presenter MUST call the topology overload.
decision | TopologySnapshot.display(_:) is not declared yet (Display.swift says the topology ticket adds it), so the overload builds a key->frame dictionary from topology.displays instead of editing ZonesCore.
decision | KNOWN LIMIT: Highlight has one display, so a Span suspended on Display A while the highlight sits on Display B cannot be drawn on A by apply. AC-085 (manual) and the reducer's choice of Highlight.display decide later.
decision | ZoneDrawing, PanelStyle, PanelModel were undeclared by T01, so they are declared in OverlayModel.swift with public memberwise inits.
decision | ZonesWindowingTests depends on ZonesTestSupport, so the slice-6 property test is in scope.
2:36 AM PT | slice 1 | zonesWithinVisibleFrame | green | d20ca62
2:36 AM PT | slice 2 | highlightDistinctAtLowOpacity | green | 3ac63cc
2:37 AM PT | slice 3 | applyPaintsPrimarySecondaryDim | green | b87635c
decision | slice 4 test passed on first run: panels (slice 1) already routes labels through LabelModel (T12), so no new production code; the test pins the AC-063 behavior.
2:37 AM PT | slice 4 | labelsLegibleAndScaled | green | pending
