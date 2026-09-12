# Ghostty triple periods implementation plan

**Goal:** User approved retaining immediate Chinese full stops in Ghostty and synthesizing two Backspace keys followed by three ASCII dots on the third standalone dot.

**Architecture:** Keep verified document replacement unchanged. Add an explicit Ghostty-only event fallback to PeriodSequence. Send one ordered batch of key down/up pairs directly to the foreground Ghostty PID, tag synthetic events so the IME passes them through, and preserve the existing reset generation/lifecycle hooks. Prepare all events before posting; if access or target validation fails, commit the ordinary third Chinese period. No delayed timers, clipboard, Lua, or global event destinations.

**Tech stack:** Swift, InputMethodKit, CoreGraphics, existing NSTextView and real Rime tests.

1. Add failing tests to tests/spacing/PeriodTests.swift for event-only counting, immediate first/second commits, third/sixth conversion, disabled fallback, reset on other key/modifier/pointer/focus, reentrancy, client identity changes, and failed emission returning ordinary punctuation. Test exact generated event key codes, flags, Unicode and marker through a pure event factory; tests do not post events to the desktop.
2. Extend sources/PeriodSequence.swift with opt-in fallback state and injected emission closure. Preserve the verified path. Eligibility still excludes composition, ASCII modes and modified keys. Reset before emitting a replacement, never restore state invalidated during insertion.
3. Add sources/GhosttyPeriodKeys.swift with CGEvent construction and PID-targeted emission guarded by CGPreflightPostEventAccess and frontmost Ghostty. Add a narrow controller setting punctuation/ghostty_backspace. Add tagged-event bypass before normal key processing. Add command line preflight/request helpers for the installed app's posting permission.
4. Update Xcode source entries, scripts/spacing/test.sh and example config. Document authorization and limitations: event-only tracking cannot observe all terminal-side edits, application-specific Backspace behavior, and asynchronous OS delivery cannot be treated as verified document replacement. No generic enablement for Slack or other apps.
5. Run focused red/green tests, full bash scripts/spacing/test.sh, full isolated schema input checks, build and signature checks. Review implementation before commit. Back up live app/config, install, restart only isolated dev input method, check installed permission and config. If macOS permission is absent, request it from the installed app; user must grant it in System Settings before real delivery can be validated. Never claim desktop delivery verified from an event-factory test.
6. Commit/push only relevant files to origin feature/context-aware-spacing and verify remote HEAD.

Review additions accepted: real-engine events-only commit receipt test; failed emission followed by a fresh sequence; reentrant reset during emission. Synchronous batch submission is not atomic OS delivery; same-app focus changes and physical keys may interleave. Both plan rounds and code review use a native reviewer agent.
