# Property tests use a small seeded generator in ZonesTestSupport

Swift Testing has no property-test support. A ~60-line seeded pseudo-random generator with shrink-free fixed seeds gives reproducible layout-math tests without a dependency. Rejected: swift-check (dependency for one package).
