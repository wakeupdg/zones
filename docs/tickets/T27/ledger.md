# T27 ledger
- gap: ShortcutAction.allCases is 14 with isWindowAction true for first 12 (checked, no fix needed).
- gap: Core Preferences.defaultShortcuts used letter("r")/("e"); changed to uppercase "R"/"E" per brief (letters stored uppercase); ShortcutRules.defaults returns it.
- slice 1: ShortcutStoreTests.defaultsMatchADR green — ShortcutRules.defaults (ChordWarning, RecorderState declared)
- slice 2: ShortcutStoreTests.requiresCommandOrControl green — ShortcutRules.validate
- slice 3: ShortcutStoreTests.recorderStateTable green — ShortcutRules.recorderState
