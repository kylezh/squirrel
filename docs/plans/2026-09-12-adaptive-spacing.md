# Adaptive spacing implementation plan

**Goal:** Honor the user's request to enable spacing globally and retain spacing when an application cannot expose its text context.

**Architecture:** Add `adaptive` beside the existing strict `verified` and query-free `events_only` modes. Use snapshots when available, fall back to event continuity when unavailable, and keep explicit selection/edit/focus/pointer invalidation. An unavailable query must not be confused with a known replacement selection or a confirmed insertion mismatch.

**Tech stack:** Swift, InputMethodKit, librime/librime-lua, YAML.

1. Add failing native and real-engine tests covering unavailable queries, both spacing directions, capability transitions, replacement selections, newline/pointer resets, and failed insertion confirmation.
2. Distinguish unavailable/invalid probe results. Extend tracker/context handling without changing Lua or upstream controller hooks.
3. Run `scripts/spacing/test.sh`, build the development bundle, and review the change.
4. Back up the installed development app/configuration, install the rebuilt app, set global mode to `adaptive`, remove the TextEdit-only override, and restart only the development input source. Verify the compiled configuration and selected source.
5. Update usage documentation, keep the feature change in a focused commit, and push the fork branch.

Always-verified would suppress spacing in unsupported apps. Always-events-only would discard useful context checks even in supported apps. Adaptive mode implements the requested fallback while retaining available checks; it cannot detect external edits that expose neither an event nor readable context.
