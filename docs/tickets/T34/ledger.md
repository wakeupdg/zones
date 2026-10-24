# T34 ledger
- slice 1: SettingsPanesSmokeTests.preferencesControllerPersists green — PreferencesController (App/Settings) coerces via Preferences.coerced() and writes PreferencesCodec blob to zones.preferences
- slice 2: SettingsPaneFlowTests.exportAllAndOne green — new Sources/ZonesWindowing/Settings/LayoutsFlow.swift (state, exportDocument, writeExport via one codec)
- slice 3: SettingsPaneFlowTests.importMergeReplaceSheet green — LayoutsFlow.beginImport/cancelImport/replaceBackupName/applyImport (backup first, both documents saved, dormant reported); added public DocumentStore.saveBackup(_:named:) in ZonesCore/DocumentStore+Raw.swift
