# Punctuation paging and continuous literal input

Merge the patch in [pending_url.yaml](../../config/spacing/pending_url.yaml)
into `rime_ice.custom.yaml` and redeploy. This profile uses built-in Rime key
bindings, recognition and echo translation, with no new Lua or native rebuild.

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

Starting with two or more dots recognizes a literal punctuation sequence before
key bindings: `...` and `......` each remain one exact raw candidate, confirmed
with Space or Return. A dot typed while a word's candidates are visible still
pages, so this does not turn repeated candidate paging into literal dots.

A dot entered with no composition offers `。` for confirmation with Space;
`nihao` + Space + `.` + Space commits `你好。`. Return retains Rime Ice's raw-input
commit behavior. Commas outside paging and numeric separators retain their
existing punctuation behavior. Backspace edits literal input and Escape cancels
it without committing.

Run the real-engine checks against an isolated deployed copy of the complete
personal configuration, never the running input method's data directory:

```sh
cc -I librime/src tests/spacing/RimeIceInputBehavior.c -o build/spacing/input-behavior
build/spacing/input-behavior "$PWD" /path/to/isolated/user-data
```

Checks include initial comma commit, repeated dot/comma paging, returning to the
first page, Control-F/B/N/P/A navigation, boundary behavior, passthrough and
selection in all four panel layouts, state reset after selection,
continuous `x.com`, literal ellipses, hyphens, literal case preservation, Return,
Backspace, Escape and numeric selection/punctuation.
