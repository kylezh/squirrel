# Context-aware mixed Chinese/English spacing

This fork adds an opt-in frontend context bridge and a Lua processor. Current base: upstream master snapshot `0cd71a6130a5866b0ae6ba0494929ebdc8211194`. Development started on Squirrel 1.1.2 and the initial four-patch series was then rebased onto this snapshot, followed by a focused input-source identity fix. The original series is retained locally as `backup/spacing-1.1.2`. The upstream branch and input dictionaries are unchanged. Do not run the stock `make install` while trying the development bundle.

## Build and test

```sh
git submodule update --init librime
bash action-install.sh
scripts/spacing/test.sh
scripts/spacing/build-dev.sh
```

The upstream dependency script pins librime 1.17.0 and Sparkle 2.6.2; it also downloads default schemas through plum. Our integration tests use their own checked-in tiny dictionary, not those moving dictionaries. `build-dev.sh` uses the selected Xcode SDK and `swiftc`, so it does not need the Xcode IDE's simulator plugins. The regular Xcode target also includes the new Swift files.

Output: `build/spacing/SquirrelSpacingDev.app`, ad-hoc signed for this machine. The script does **not** install, enable, or switch input sources. The app has a separate bundle ID/IMK connection, uses `~/Library/RimeSpacingDev`, and disables the official Sparkle updater. It is designed to coexist with the original input method, but system activation remains unverified (see installation finding below). Command-line input-source registration helpers inherited from upstream still name the official IDs; use macOS Input Sources settings when trying this development identity.

To try it manually, put the development bundle in your user `~/Library/Input Methods/`, add its input source in macOS settings (a logout/login may be necessary), and copy your Rime configuration into `~/Library/RimeSpacingDev`. Copy from a consistent backup; never symlink the production user database into the development directory. Merge the two sample patches from `config/spacing/`, and copy its Lua module to the development directory's `lua/`. Redeploy the development directory using the bundled `rime_deployer --build` and its `Contents/SharedSupport` directory. The upstream `--reload` notification is shared, so avoid using it for isolated trials.

Default: spacing is off. The sample explicitly enables verified mode only for TextEdit as a starting point for manual testing. Other apps need an explicit mode or a consciously selected global mode. `verified` requires a collapsed selection (or the current marked-text range) and a valid short text snapshot. `events_only` avoids document queries and has weaker guarantees. `off` leaves input behavior alone. Changing frontend config takes effect after redeploy and reactivation/restarting the development input source.

## Behavior

Adjacent commits such as `hello` + `中文` become `hello 中文`; the inverse also works. Existing whitespace/punctuation breaks the boundary. ASCII letters participate; digits and formatting inside a single candidate are not changed.

The bridge resets on external mouse down, focus/input-source changes, document editing keys, unhandled editing commands, or mismatched selection/short text. Normal marked-text changes, candidate selection, and plain Cmd+C/Cmd+S retain a verified boundary. Other modified shortcuts conservatively reset. All shortcuts are still delivered to the target app.

A global **mouse-only** observer excludes our process, so clicking the custom candidate panel is not treated as a document click. It does not intercept or synthesize events. Input source and workspace observers complement IMK activation/deactivation. Ordinary pointer movement/scrolling does not invalidate. Unsupported document queries suppress spacing. A new session never borrows another session's boundary.

## Bridge contract

A fixed-field, versioned ASCII protocol is used instead of the draft JSON illustration, avoiding a new JSON dependency in librime-lua. Fields cannot contain separators or free-form text:

```
squirrel_spacing_context = 1|session-UUID|epoch|empty-or-tracking-or-uncertain-or-suspended
squirrel_spacing_receipt = 1|session-UUID|epoch|UTF8-byte-count|FNV1a32
```

The context property is published synchronously before processing input. Lua reads it on initialization and observes changes; missing/invalid versions disable spacing. New epochs clear its language boundary. Inactive/unverifiable states cannot rearm the boundary.

Receipts describe the bytes Lua accounted for in the current commit batch, including an inserted prefix. They contain no plaintext and are a consistency check, not a security/authentication mechanism. The frontend matches the final Rime commit and clears the receipt after consumption. Unobserved direct commits (for example another Lua's `engine:commit_text`) are inserted unchanged and invalidate old state. There is only one spacing writer, in Lua; the frontend never adds a second prefix. Actual application insertion is checked against the expected UTF-16 position and short suffix.

`InputContinuityTracker.swift` is a pure state machine. `InputContextProbe.swift` isolates IMK text queries. `SpacingContext.swift` owns observation and publication. `SquirrelInputController.swift` only wires lifecycle/key/commit hooks. Tests use `NSTextView` through an IMKTextInput adapter plus the real bundled librime/lua, rather than assuming C API tests prove system event delivery.

## Verification status and limits

Automated checks cover the pure state machine, Lua handshake and stale epochs, native marked text/selection/commit behavior, and end-to-end in-process librime-to-NSTextView spacing. They also verify foreign direct commits, prefix receipts, copies, newline handling, unsupported queries, and exact separation of official/development input-source IDs used by status visibility and composition cleanup. Run `scripts/spacing/test.sh` for current evidence.

Real OS dispatch and application compatibility (TextEdit, browsers, Electron/chat apps, terminals, remote desktops), focus-event races, app-specific undo grouping, and input latency still require a manual trial with the development input source. The in-process adapter does not certify these. Global event monitors are asynchronous and short snapshots do not prove all document changes were observed. No universal compatibility claim is made. Terminal/remote use should remain off until explicitly tested.

Installation finding (2026-09-12, macOS 26.6.2): the development bundle was copied into the user's Input Methods directory, its independent dictionary/configuration deployed, and the process launched successfully. However, TIS registration only exposed temporary entries; enabling returned success without enabling the parent input method, selection returned `-50`, and System Settings did not list the development source. `codesign --verify` passed while `spctl --assess --type execute` rejected the ad-hoc bundle. No signing identities were available on this machine. These are distinct checks: successful compilation/signature integrity does not establish system acceptance. Activation is still blocked; logout was not attempted and is not promised to fix it. A [separate IMK project's macOS 26 investigation](https://github.com/ptrinh/viettelex/blob/main/docs/MACOS_IME_NOTES.md) reports a notarization requirement; this is a working hypothesis here, not a diagnosis confirmed by Apple's logs. Developer ID signing/notarization is the next supported path to evaluate.

The selected Xcode installation on the initial development machine had an IDE plugin/shared framework version mismatch; its `xcodebuild` failed before compiling project sources. All Swift app sources can instead be compiled and linked through `build-dev.sh`. Normal Xcode builds should be checked again after repairing that local installation.

No text, clipboard data, or key characters are logged by the bridge. Only up to 32 UTF-16 units of preceding text are retained in memory and discarded on invalidation/focus exit. There is no background text polling and no Accessibility permission requirement in this implementation. IMK queries are synchronous; slow clients need to be disabled or set to explicitly weaker events-only mode.

## Upgrade / rebase

Keep `upstream` pointing at `rime/squirrel`, `origin` at your fork. Work on `feature/context-aware-spacing`, leaving master as an upstream reference. Local `rerere.enabled=true` remembers resolutions; autostash is off so uncommitted user changes are not hidden.

```sh
git fetch upstream --tags
scripts/spacing/check-rebase.sh upstream/master
```

The check uses a disposable worktree, replays the **committed** patch series and runs standalone Swift/Lua/native tests. It leaves your current branch unchanged, reports conflicts, and removes its worktree even on failure. It does not claim to validate the rebased full app/dependencies.

For a real update, start with a clean worktree and retain a recovery ref:

```sh
git branch backup/spacing-before-upgrade
git rebase upstream/master
git submodule update --init librime
bash action-install.sh
scripts/spacing/test.sh
scripts/spacing/build-dev.sh
```

Use a fresh name for the backup branch each time. Resolve conflicts only in the thin controller hooks/project declarations; keep the standalone modules intact where possible. Check upstream lifecycle/commit changes rather than blindly choosing ours. `git rebase --abort` returns to the original branch on failure. When publishing rewritten history, use `git push --force-with-lease origin feature/context-aware-spacing`, never plain force. Coordinate if anyone else has started using that branch.

Do not push experimental behavior to upstream master. If submitting upstream later, the context bridge and Lua spacing policy can be proposed separately. The initial real upgrade required resolving controller lifecycle/direct-commit hooks and the app delegate updater initialization; upstream status-bar and forced-marked-text fixes were retained. Local rerere records those resolutions. A successful current replay does not guarantee future conflict-free rebases.

## Rollback

Set `spacing_context/enabled: false` and redeploy to disable the bridge, or select the original official input source. Never overwrite the production `~/Library/Rime` when rolling back. Export/merge new learned words separately if you want to retain development-session learning. Keep the official input method installed during trials.
