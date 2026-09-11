//
//  InputContinuityTracker.swift
//  Squirrel
//

import Foundation

struct InputContinuityTracker {
  enum Mode: String {
    case off, verified, adaptive
    case eventsOnly = "events_only"
  }
  enum State: String { case suspended, empty, tracking, uncertain }
  enum Reason: String {
    case activate, pointer, edit, focus, snapshot, commit, passthrough, session, schema
  }

  struct Snapshot: Equatable {
    let location: Int
    let before: String
    var marked: NSRange?

    func matches(_ other: Snapshot) -> Bool {
      location == other.location && before == other.before
    }
  }

  let identifier = UUID().uuidString
  private(set) var epoch: UInt64 = 0
  private(set) var state: State = .suspended
  private(set) var reason: Reason = .session
  private(set) var mode: Mode = .off
  private var expected: Snapshot?

  // Fixed fields carry no client text and require no JSON dependency in Lua.
  var message: String { "1|\(identifier)|\(epoch)|\(state.rawValue)" }

  func matchesReceipt(_ receipt: String, text: String) -> Bool {
    let parts = receipt.split(separator: "|")
    guard parts.count == 5, parts[0] == "1", parts[1] == Substring(identifier),
      UInt64(parts[2]) == epoch, Int(parts[3]) == text.utf8.count
    else { return false }
    let checksum = text.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
    return UInt32(parts[4]) == checksum
  }

  mutating func activate(mode: Mode) {
    self.mode = mode
    reset(to: mode == .off ? .suspended : .empty, reason: .activate)
  }

  mutating func suspend() { reset(to: .suspended, reason: .focus) }

  mutating func invalidate(reason: Reason) {
    reset(to: state == .suspended ? .suspended : .empty, reason: reason)
  }

  mutating func prepare(snapshot: Snapshot?) {
    guard state != .suspended else { return }
    if mode == .verified && snapshot == nil {
      if state != .uncertain { reset(to: .uncertain, reason: .snapshot) }
      return
    }
    if let expected, let snapshot, !expected.matches(snapshot) {
      reset(to: .empty, reason: .snapshot)
    } else if state == .uncertain {
      reset(to: .empty, reason: .snapshot)
    }
    expected = snapshot
  }

  mutating func didCommit(snapshot: Snapshot?) {
    guard state != .suspended else { return }
    if mode == .verified && snapshot == nil {
      reset(to: .uncertain, reason: .commit)
      return
    }
    expected = snapshot
    state = .tracking
    reason = .commit
  }

  mutating func expectPassthrough(_ text: String, from snapshot: Snapshot?) {
    guard state != .suspended else { return }
    if let snapshot, snapshot.marked == nil {
      let prefix = snapshot.before + text
      expected = Snapshot(
        location: snapshot.location + text.utf16.count,
        before: Self.suffix(prefix), marked: nil)
      state = .tracking
    } else if mode == .eventsOnly || mode == .adaptive {
      expected = nil
      state = .tracking
    } else {
      reset(to: .uncertain, reason: .passthrough)
    }
  }

  static func suffix(_ text: String) -> String {
    let units = Array(text.utf16.suffix(32))
    let start = units.first.map { (0xDC00...0xDFFF).contains($0) ? 1 : 0 } ?? 0
    return String(decoding: units.dropFirst(start), as: UTF16.self)
  }

  private mutating func reset(to state: State, reason: Reason) {
    epoch &+= 1
    self.state = state
    self.reason = reason
    expected = nil
  }
}
