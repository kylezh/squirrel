//
//  SpacingContext.swift
//  Squirrel
//

import InputMethodKit

final class SpacingContext {
  private var tracker = InputContinuityTracker()
  private var mode: InputContinuityTracker.Mode = .off
  private var session: UInt = 0
  private var target: ObjectIdentifier?
  private var mouseMonitor: Any?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var inputSourceObserver: NSObjectProtocol?
  private var lastMessage = ""
  private var snapshotBeforeKey: InputContinuityTracker.Snapshot?
  private var commitCount = 0
  private var commitsBeforeKey = 0
  private let publish: (String) -> Void

  init(publish: @escaping (String) -> Void) { self.publish = publish }

  func activate(session: UInt, client: IMKTextInput?, mode: InputContinuityTracker.Mode) {
    stopMonitoring()
    snapshotBeforeKey = nil
    if self.session != session { tracker = InputContinuityTracker() }
    self.session = session
    self.mode = mode
    target = client.map { ObjectIdentifier($0 as AnyObject) }
    tracker.activate(mode: mode)
    send()
    guard mode != .off else { return }
    // Global monitors exclude our own nonactivating candidate window.
    mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]) { [weak self] _ in
      self?.invalidate(.pointer)
    }
    let center = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification,
      NSWorkspace.screensDidSleepNotification,
    ] {
      workspaceObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          self?.suspend()
        })
    }
    inputSourceObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil, queue: .main
    ) { [weak self] _ in self?.suspend() }
  }

  func ensureActive(session: UInt, client: IMKTextInput?, mode: InputContinuityTracker.Mode) {
    let newTarget = client.map { ObjectIdentifier($0 as AnyObject) }
    if self.session != session || self.mode != mode || target != newTarget
      || tracker.state == .suspended
    {
      activate(session: session, client: client, mode: mode)
    }
  }

  func suspend() {
    snapshotBeforeKey = nil
    tracker.suspend()
    send()
    stopMonitoring()
  }

  func invalidate(_ reason: InputContinuityTracker.Reason) {
    snapshotBeforeKey = nil
    tracker.invalidate(reason: reason)
    send()
  }

  func prepare(client: IMKTextInput?) {
    guard mode != .off else { return }
    tracker.prepare(snapshot: snapshot(client))
    send()
  }

  func beforeKey(_ event: NSEvent, client: IMKTextInput?, composing: Bool) {
    guard mode != .off else { return }
    prepare(client: client)
    snapshotBeforeKey = snapshot(client)
    commitsBeforeKey = commitCount
    guard event.type == .keyDown else { return }
    if Self.isReadOnlyShortcut(event) { return }
    // Let the app handle shortcuts; invalidate before its unobserved edit.
    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
      || event.modifierFlags.contains(.option)
    {
      invalidate(.edit)
    } else if !composing && Self.isEditingKey(event.keyCode) {
      invalidate(.edit)
    }
  }

  func afterKey(_ event: NSEvent, handled: Bool, client: IMKTextInput?) {
    guard mode != .off, event.type == .keyDown, !handled else { return }
    if Self.isReadOnlyShortcut(event) { return }
    if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
      let chars = event.characters, !chars.isEmpty,
      chars.unicodeScalars.allSatisfy({ (32...126).contains($0.value) })
    {
      // A prefix space may already have been committed by the Lua callback.
      let anchor = commitCount == commitsBeforeKey ? snapshotBeforeKey : snapshot(client)
      tracker.expectPassthrough(chars, from: anchor)
      send()
    } else {
      invalidate(.edit)
    }
  }

  func beforeCommit(client: IMKTextInput?) -> InputContinuityTracker.Snapshot? {
    mode == .off ? nil : snapshot(client)
  }

  func acceptsReceipt(_ receipt: String, text: String) -> Bool {
    tracker.matchesReceipt(receipt, text: text)
  }

  func didCommit(
    _ text: String, before: InputContinuityTracker.Snapshot?, client: IMKTextInput?,
    observed: Bool = true
  ) {
    guard mode != .off else { return }
    commitCount += 1
    guard observed else {
      invalidate(.commit)
      return
    }
    let after = snapshot(client)
    if mode == .verified {
      guard let before, let after, after.marked == nil,
        after.location == before.location + text.utf16.count,
        after.before == InputContinuityTracker.suffix(before.before + text)
      else {
        tracker.prepare(snapshot: nil)
        send()
        return
      }
    }
    tracker.didCommit(snapshot: after)
    send()
  }

  private func snapshot(_ client: IMKTextInput?) -> InputContinuityTracker.Snapshot? {
    // Compatibility mode deliberately avoids synchronous document queries.
    mode == .verified ? InputContextProbe.snapshot(client: client) : nil
  }

  private func send() {
    let message = tracker.message
    if message != lastMessage {
      lastMessage = message
      publish(message)
    }
  }

  private static func isReadOnlyShortcut(_ event: NSEvent) -> Bool {
    event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
      && ["c", "s"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "")
  }

  private static func isEditingKey(_ code: UInt16) -> Bool {
    // Return, keypad Enter, Tab, Escape, deletion, and document navigation.
    [36, 76, 48, 53, 51, 117, 115, 119, 116, 121, 123, 124, 125, 126].contains(code)
  }

  private func stopMonitoring() {
    if let mouseMonitor {
      NSEvent.removeMonitor(mouseMonitor)
      self.mouseMonitor = nil
    }
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers.removeAll()
    if let inputSourceObserver {
      DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
      self.inputSourceObserver = nil
    }
  }

  deinit { stopMonitoring() }
}
