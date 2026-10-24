# T35 ledger
- slice 1: EditorWindowTests.defaultFrameEqualsVisibleFrame green — makeWindow opens on editorFrame, resizable, non-opaque 0.25 backdrop
- slice 2: EditorWindowTests.keyEquivalentsMapToEvents green — EditorKeyMap letters and Command combos
- slice 3: EditorWindowTests.arrowKeysNudgeSelectedDivider green — arrows nudge selection, Left/Up -1, Right/Down +1, Shift x10
- slice 4: EditorWindowTests.effectsRouteToStores green — EditorEffectRouter sends layouts/assignments to DocumentStore, replaceLive upsert, prompt/error/close to sink
- slice 5: EditorWindowTests.zoneRectsEqualResolvedFrames green — EditorCanvasGeometry.zoneRects shifts preview frames by content origin only
- slice 6: EditorWindowTests.dividerDragProducesSetRatio green — EditorCanvasGeometry.dividers and event(forDragOf:to:optionHeld:), snap off with Option
- slice 7: EditorWindowTests.displaySwitcherListsDisconnectedAndPrompts green — EditorToolbarModel.displayChoices, pick and confirm switch events
- slice 8: EditorWindowTests.slidersAndTemplatePickerSendCommands green — Margin/Gap sliders clamp 0...64 whole points, Template picker maps to .template(t, count:)
