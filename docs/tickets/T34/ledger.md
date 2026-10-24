# T34 ledger
- slice 1: SettingsPanesSmokeTests.preferencesControllerPersists green — PreferencesController (App/Settings) coerces via Preferences.coerced() and writes PreferencesCodec blob to zones.preferences
- slice 2: SettingsPaneFlowTests.exportAllAndOne green — new Sources/ZonesWindowing/Settings/LayoutsFlow.swift (state, exportDocument, writeExport via one codec)
