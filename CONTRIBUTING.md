# Contributing

Start with an issue for a new device or a substantial interface change. A small,
dependable menu bar app is the goal.

1. Describe the problem and how to reproduce it.
2. Keep changes focused and use native macOS APIs where practical.
3. Run `swift test` and a release build. Format Swift with `swift-format` and the
   repository configuration.
4. Test on real hardware when changing packets or timing.
5. Describe what you tested and what remains unverified in your pull request.

Keep public documentation and code comments in English. User-facing strings use
the English/Spanish helper. Persistent identifiers must not depend on translated
labels. Comments should explain constraints or intent rather than repeat the code.

Bound all polling and media buffers. Measure changes to capture, idle behavior or
memory. New features should fit the menu rather than introduce a main window.

Device reports should include the advertised name, original phone app, macOS
version and confirmed behavior. A successful write does not prove individual-LED
support. Never post private messages, signing credentials or unredacted identifiers.
