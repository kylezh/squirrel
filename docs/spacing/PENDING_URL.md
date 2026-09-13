# Punctuation paging and continuous literal input

Merge the patch in [pending_url.yaml](../../config/spacing/pending_url.yaml)
into `rime_ice.custom.yaml` and redeploy. This profile uses built-in Rime key
bindings, recognition and echo translation. Immediate full stops use this patch;
triple-dot conversion additionally requires the native frontend described below.
No additional Lua module is needed.

With ordinary candidates visible, `.` goes to the next page. Before paging,
`,` commits the selected candidate and a comma. Once Rime's `paging` state is
active, `,` goes to the previous page and never commits text, even after returning
to the first page. Selecting a candidate or cancelling the composition resets
that state for new input. The comma binding uses Rime's native `paging`
condition, which also becomes active during candidate navigation.
Page Up / Page Down remain available.

While candidates are visible, Control-F highlights the next candidate,
Control-B the previous candidate, Control-N the next page, Control-P the
previous page, and Control-A the first candidate on the first page. With no
candidates these shortcuts reach the application as usual.

Control-A/B/F bind directly to selector actions for each panel layout, avoiding
layout-dependent arrow keys. The key binder redispatches these three keys to
the selector with its built-in recursion guard. It consumes the outer key even
when the selector cannot move further; pressing Control-B or Control-A at the
first candidate therefore neither moves the pinyin caret nor leaks a shortcut
to the application. Page keys retain Rime's native highlight-offset behavior.

A single paging dot followed immediately by a lowercase letter is reinterpreted
by Rime as literal input. Thus `x` → `.` initially displays the next candidate
page without committing; continuing with `com` restores `x.com` as the sole raw
candidate, and Return commits the complete address. Repeated paging punctuation
stays paging when a word is being composed. The recognizer requires text after
the first dot so it does not steal the initial paging key. Explicit protocol
prefixes and already recognized literal addresses continue to accept punctuation
as text.

A hyphen after an alphabetic prefix starts literal input immediately, allowing
`abc-def`, `abc-123` and `foo-bar.com`. This takes precedence over the minus-key
paging shortcut. Pre-delimiter numeric candidate selection still works; use
ASCII mode for prefixes that conflict with selection keys or the first-dot
reinterpretation rule.

`echo_translator` supplies the raw candidate and must precede normal translators:
appending it exposed a numeric-punctuation regression with this filter pipeline.
The existing capitalization filter is restricted to word tags, preserving literal
address case. Its patch index assumes this fork's Rime Ice English-learning
profile; retain the correct filter position if upstream reorders the schema.

With no composition, each `.` immediately commits `。`: `nihao` + Space + `.`
commits `你好。` without another confirmation key. In the updated native bundle,
set `punctuation/three_periods: true` in `squirrel.custom.yaml` (included in the
sample frontend patch). Three consecutive standalone period keystrokes then
produce `。` → `。。` → `...`; six produce `......`. There is no delay or timer.
A dot while a word's candidates are visible still pages, and ASCII/numeric dots
retain their existing behavior.

`PeriodSequence` replaces exactly the two preceding UTF-16 code units only after
verifying that they are this controller's own two consecutive `。` commits in the
same client, with an unchanged unmarked caret and no selection. Other keys,
modifier changes, mouse clicks, lifecycle transitions or mismatching document
snapshots clear the sequence. Post-insert verification and a reset generation
protect against stale snapshots and reentrant client callbacks. Replacement
invalidates spacing continuity; subsequent text cannot inherit a stale boundary.

Conversion requires readable context and an application honoring IMK's explicit
replacement range. It is enabled only in verified/adaptive spacing modes. The
existing Ghostty and Slack events_only overrides, disabled spacing, and clients
with unavailable or stale context keep immediate `。。。`; no backspaces are
synthesized and no blind document edit is attempted. The frontend does not try a
second correction if a client ignores replacementRange.

Return retains raw-input commit behavior inside an unfinished composition.
Commas outside paging, numeric separators and literal address editing retain
their existing behavior.

Run the real-engine checks against an isolated deployed copy of the complete
personal configuration, never the running input method's data directory:

```sh
cc -I librime/src tests/spacing/RimeIceInputBehavior.c -o build/spacing/input-behavior
build/spacing/input-behavior "$PWD" /path/to/isolated/user-data
```

Checks include initial comma commit, repeated dot/comma paging, returning to the
first page, Control-F/B/N/P/A navigation, boundary behavior, passthrough and
selection in all four panel layouts, state reset after selection,
continuous `x.com`, immediate full stops, hyphens, literal case preservation,
Return, Backspace, Escape and numeric selection/punctuation. Rime-only tests
expect `。。。`; conversion belongs to the native frontend, tested with actual
NSTextView in `PeriodTests.swift` and the punctuation-enabled real-engine fixture.
Run all native, Lua and engine tests with `bash scripts/spacing/test.sh`.

When a raw digit follows committed Chinese, `mixed_spacing` inserts a prefix
space during Rime's unhandled-key notification. It then appends the passthrough
key to commit history, because Rime recorded that key before the notification
and `commit_text(" ")` otherwise makes the space the latest record. Native
numeric punctuation can consequently recognize `中文` + `5.4` as `中文 5.4`,
including in events-only terminal mode. This uses Rime's existing digit separator
rules; ordinary Chinese full stops and candidate-number selection are unchanged.
