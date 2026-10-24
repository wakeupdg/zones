T02 started
- slice 1: GeneratorTests.failureMessageNamesSeed green — Generator.failureMessage now embeds String(describing: layout); Generator and FakeClock already existed from T01
- slice 2: FakeContractTests.windowSystem green — FakeWindowSystem plus shared ResponseQueue/CallRecorder/StreamBox helpers (latency via FakeClock .frameSample timers; calls vs completed)
