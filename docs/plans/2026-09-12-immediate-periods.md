# Immediate periods and verified triple-dot conversion

The user approved: while Chinese candidates exist, period remains a paging key;
otherwise a period immediately commits `。`, and the third consecutive period
replaces the two previous, already committed `。` with `...`. Clear the sequence
on other keys, pointer actions, focus/session/schema changes and caret changes.
Unsupported document clients keep ordinary immediate periods.

## Implementation plan

**Goal:** Preserve immediate punctuation and candidate paging while converting
three isolated period keystrokes into literal ASCII ellipsis in readable clients.

**Architecture:** A small native `PeriodSequence` component owns at most two
verified punctuation commits. Rime commits punctuation normally. At the frontend
commit boundary, the third dot replaces precisely the two UTF-16 code units before
the caret, only if the current unmarked, unselected snapshot matches the recorded
snapshot and ends in `。。`. No synthetic backspaces or time-delayed commits.

**Tech stack:** Swift, IMKTextInput, NSTextView, existing librime C API tests.

1. Add failing tests in `tests/spacing/PeriodTests.swift` using real NSTextView:
   immediate first/second periods, third replacement, six periods, emoji prefix,
   other key/newline/backspace/modifier reset, pointer/focus/session reset,
   moved caret, nonempty selection, unsupported/stale query, unrelated existing
   punctuation, and no conversion during pinyin/ASCII mode or when disabled.
   Test the actual new component's insert path; observe replacement ranges.
2. Implement `sources/PeriodSequence.swift`: prepare eligibility on key events;
   `insert(text, before, client, ordinaryInsert)` delegates normal insertion or
   performs a verified range replacement. Only confirm state after a matching
   post-insert snapshot. A generation counter prevents reentrant lifecycle resets
   during insert from being overwritten. Bind tracked state to client identity.
3. Add a default no-op reset callback to `SpacingContext`, invoked by activate,
   suspend and explicit invalidate. Wire it to PeriodSequence in the controller.
   Call prepare after spacing.beforeKey. Enable through opt-in
   `punctuation/three_periods: true` only when spacing mode reads documents
   (verified/adaptive); events_only/off never gain document queries from this.
   At commit, use the component around ordinary insert+spacing.didCommit.
   After a replacement invalidate the spacing boundary; leave Rime's committed
   punctuation receipt consumed normally. Run the conversion decision before
   the force_marked_text_for_direct_commit workaround; put that entire workaround
   in ordinaryInsert and test that mode. No changes to dictionary learning.
4. Set both full/half-shape dot mappings to `{commit: "。"}` in the public patch
   and isolated real config. Set punctuation/three_periods: true in public and
   live squirrel.custom.yaml; install this frontend config as well as the schema.
   Keep candidate/URL shortcuts. Update the C test's
   standalone-dot expectations: without the frontend triple dots are `。。。`.
   Keep domain, paging, comma, digit and abbreviation coverage.
5. Add a tiny punctuation-enabled librime fixture and engine/NSTextView tests
   exercising the same native insertion component, including Chinese -> dots ->
   English, no accidental spaces, numeric dots, candidate paging and ASCII mode.
   Wire new source into the Xcode project, test script and automatic native build.
6. Run focused failing then passing tests, complete scripts/spacing/test.sh,
   full isolated input-behavior test, build-dev.sh and signature checks.
   Document supported behavior and fallback in docs/spacing/PENDING_URL.md.
7. Back up live app and changed configuration; select ABC, quit and wait for the
   old process. Install the verified native bundle/config without copying test
   user DBs. Reactivate dev source, verify new process, compiled schema, binary
   and signature. Commit only source/tests/public config/docs, push origin's
   feature/context-aware-spacing and verify remote HEAD.

The input method cannot prove that an arbitrary client honors replacementRange;
the feature requires a client implementing that protocol. It does not attempt a
second destructive correction if an application ignores it. Existing Ghostty and
Slack events_only overrides deliberately do not perform retroactive conversion.
