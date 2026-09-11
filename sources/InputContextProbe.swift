//
//  InputContextProbe.swift
//  Squirrel
//

import InputMethodKit

struct InputContextProbe {
  enum Result {
    case available(InputContinuityTracker.Snapshot)
    case unavailable
    case invalidSelection

    var snapshot: InputContinuityTracker.Snapshot? {
      if case .available(let snapshot) = self { return snapshot }
      return nil
    }
  }

  static func snapshot(client: IMKTextInput?) -> InputContinuityTracker.Snapshot? {
    read(client: client).snapshot
  }

  static func read(client: IMKTextInput?) -> Result {
    guard let client else { return .unavailable }
    let selection = client.selectedRange()
    guard selection.location != NSNotFound, selection.length != NSNotFound else {
      return .unavailable
    }
    let rawMarked = client.markedRange()
    let marked =
      rawMarked.location != NSNotFound && rawMarked.length != NSNotFound && rawMarked.length > 0
      ? rawMarked : nil
    let location: Int
    if let marked {
      guard selection.location >= marked.location,
        selection.location - marked.location <= marked.length,
        selection.length <= marked.length - (selection.location - marked.location)
      else { return .invalidSelection }
      location = marked.location
    } else {
      guard selection.length == 0 else { return .invalidSelection }
      location = selection.location
    }
    guard location >= 0 else { return .unavailable }
    let count = min(location, 32)
    if count == 0 { return .available(.init(location: location, before: "", marked: marked)) }
    let range = NSRange(location: location - count, length: count)
    guard let text = client.attributedSubstring(from: range)?.string,
      text.utf16.count == count
    else { return .unavailable }
    return .available(
      .init(location: location, before: InputContinuityTracker.suffix(text), marked: marked))
  }
}
