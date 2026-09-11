//
//  InputContextProbe.swift
//  Squirrel
//

import InputMethodKit

struct InputContextProbe {
  static func snapshot(client: IMKTextInput?) -> InputContinuityTracker.Snapshot? {
    guard let client else { return nil }
    let selection = client.selectedRange()
    guard selection.location != NSNotFound, selection.length != NSNotFound else { return nil }
    let rawMarked = client.markedRange()
    let marked =
      rawMarked.location != NSNotFound && rawMarked.length != NSNotFound && rawMarked.length > 0
      ? rawMarked : nil
    let location: Int
    if let marked {
      guard selection.location >= marked.location,
        selection.location - marked.location <= marked.length,
        selection.length <= marked.length - (selection.location - marked.location)
      else { return nil }
      location = marked.location
    } else {
      guard selection.length == 0 else { return nil }
      location = selection.location
    }
    guard location >= 0 else { return nil }
    let count = min(location, 32)
    if count == 0 { return .init(location: location, before: "", marked: marked) }
    let range = NSRange(location: location - count, length: count)
    guard let text = client.attributedSubstring(from: range)?.string,
      text.utf16.count == count
    else { return nil }
    return .init(location: location, before: InputContinuityTracker.suffix(text), marked: marked)
  }
}
