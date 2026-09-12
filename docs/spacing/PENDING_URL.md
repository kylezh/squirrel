# Pending dots, hyphens and literal address candidates

The configuration in [pending_url.yaml](../../config/spacing/pending_url.yaml)
keeps `x.` in the composition. Continuing to `x.com` produces one literal
candidate; Return commits the complete address without inserting a newline.
The same rule handles ordinary alphabetic domain prefixes, including `nihao.`.
There is no timeout and no domain whitelist.

This uses the existing recognizer, native `echo_translator`, punctuation
configuration and filter tag configuration. It adds no Lua module and requires
no native application rebuild. Merge its `patch` entries into the existing
`rime_ice.custom.yaml`, then redeploy. The capitalization-filter entry assumes
this fork's English-learning profile; retain its relative filter position if
upstream changes the schema layout.

The literal-text pattern accepts the first dot or hyphen, rather than waiting
for a later character. It runs before key bindings, so `abc-` stays in the
composition and can continue as `abc-def`, `abc-123` or `foo-bar.com`.
Hyphens after an alphabetic prefix take precedence over the minus-key paging
shortcut, including when that prefix could also be pinyin. Use Page Up /
Page Down for candidate paging (Fn+Up / Fn+Down on a standard Mac keyboard). `echo_translator` supplies a single raw candidate when no normal
translator applies. Put it **before** the normal translators: appending it
exposed a numeric-punctuation regression with this engine/filter pipeline.
Restricting the existing capitalization filter to word tags preserves the exact
case of URL hosts, paths and queries.

Once a dot or hyphen starts literal input, Return commits the complete input
exactly as typed.

Dot punctuation is a one-item selection list, not a direct commit mapping.
This also prevents dots from committing non-URL compositions such as `ni'hao.`.
A standalone Chinese full stop therefore needs selection with Space; for
example, `nihao` + Space + `.` + Space commits `你好。`. Return in an unfinished
composition retains Rime Ice's raw-input behavior. Commas keep their existing
immediate-commit behavior, including the configured ASCII comma after numbers.
Numeric separators after already committed raw digits retain the existing
numeric-punctuation setting.

Backspace can remove the dot and restore pinyin candidates; Escape cancels the
pending address. Existing pre-dot selection shortcuts remain in force: this
profile does not swallow digit selection just to anticipate a possible future
domain name. Use ASCII mode for address prefixes that conflict with those
shortcuts.

Run `tests/spacing/RimeIceInputBehavior.c` against an isolated deployed copy of
the full configuration. It checks premature commits at every address keystroke,
exact unique candidates, Return, Backspace, Escape, mixed-case paths, Chinese
punctuation, numeric punctuation and the existing abbreviation-selection rules.

```sh
cc -I librime/src tests/spacing/RimeIceInputBehavior.c -o build/spacing/input-behavior
build/spacing/input-behavior "$PWD" /path/to/isolated/user-data
```
