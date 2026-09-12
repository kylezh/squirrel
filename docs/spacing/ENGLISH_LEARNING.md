# English candidate learning

Rime Ice's uppercase filter creates new display candidates, losing the source
candidate that Rime needs for learning. English user dictionaries also match
spelling case, so learning a lowercase code does not automatically promote the
same word when its prefix is typed in uppercase.

The optional modules in `config/spacing/lua` address both parts:

- `learning_autocap_filter.lua` retains Rime Ice's capitalization behavior but
  uses `ShadowCandidate` to preserve the original candidate and its learning
  identity. It derives from Rime Ice's GPL-3.0 `autocap_filter.lua`.
- `learning_english.lua` wraps a native table translator in the configured
  namespace. For uppercase input it merges original-case and lowercase lookups
  by candidate quality, retaining exact uppercase acronyms and learned entries.
  The usual downstream `uniquifier` removes duplicates.

Copy both modules into the user data directory's `lua` folder. Replace the
English translator and capitalization filter in your scheme, keeping their
position relative to the other components:

```yaml
# Corresponding entries inside engine/translators and engine/filters:
# table_translator@melt_eng -> lua_translator@*learning_english@melt_eng
# lua_filter@*autocap_filter -> lua_filter@*learning_autocap_filter
patch:
  melt_eng/enable_user_dict: true
```

The module also supports an independent imported-term namespace, for example
`lua_translator@*learning_english@sogou_terms`. That namespace must reference a
compiled dictionary and a writable user dictionary. A `stabledb` text table is
read-only and cannot retain learning. Add a schema dependency that compiles the
secondary dictionary; merely configuring a secondary translator is insufficient.

## Imported dictionaries

Keep English codes out of the Chinese dictionary: a code such as `x z` creates
full syllables that can hide the `xz` abbreviation for Chinese words. An
independent English table uses contiguous codes such as `xz`.

For known digit-bearing terms, a finite recognizer pattern can accept prefixes
such as `k8`, `k8s`, `v2`, and `v2ray`. Add the pattern's tag to the English
translator's `tags`, alongside `abc`. Keep ordinary digit selection enabled.
An exact ambiguous sequence such as `v2` cannot simultaneously denote a term
and the original numbered-symbol shortcut; document which behavior takes
precedence. Do not globally add all digits to the Chinese speller alphabet.

A personal Chinese dictionary entry point can import the base dictionary body,
all its current import tables, and the personal supplement. Select this entry
point through the scheme's `.custom.yaml`, retaining the existing Chinese
`user_dict` name. Dictionary imports are not recursive: list the base tables
explicitly. This survives replacement of the base dictionary file; if upstream
renames or adds tables, update the personal entry point accordingly. Point any
reverse-lookup filter at the compiled personal dictionary as well.

Personal terms, finite patterns derived from them, and learned user databases
remain local and are not part of this repository.

## Verification

`bash scripts/spacing/test.sh` checks candidate identity, mixed-case result
merging, and acronym fallback. It also runs a real Rime learning fixture in two
processes: `PYRAMID` moves ahead of a higher-weight alternative after repeated
selection under `PY`, then retains its position after restarting the engine.
The fixture database is isolated from real user data.
