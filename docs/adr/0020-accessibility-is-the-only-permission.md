# Accessibility is the only TCC permission Zones asks for

Listen-only mouse taps work with the Accessibility grant (research: event-taps-tcc.md), Carbon hotkeys need none, and Zones never reads window names, so Screen Recording and Input Monitoring are never requested. Consequence: window matching uses pid plus frame, never titles.
