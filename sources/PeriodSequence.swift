import InputMethodKit

// Only replace punctuation verified to be our own two consecutive commits.
final class PeriodSequence {
  private var eligible = false
  private var count = 0
  private var expected: InputContinuityTracker.Snapshot?
  private var target: ObjectIdentifier?
  private var generation: UInt64 = 0

  func reset() {
    eligible = false
    count = 0
    expected = nil
    target = nil
    generation &+= 1
  }

  func prepare(_ event: NSEvent, enabled: Bool, composing: Bool, ascii: Bool) {
    guard enabled, !composing, !ascii, event.type == .keyDown,
      event.characters == ".",
      event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty
    else { reset(); return }
    eligible = true
  }

  // ordinaryInsert includes any client-specific marked-text workaround and
  // normal spacing bookkeeping. A replacement must bypass that whole path.
  @discardableResult
  func insert(_ text: String, before: InputContinuityTracker.Snapshot?, client: IMKTextInput,
              ordinaryInsert: () -> Void) -> Bool {
    guard eligible, text == "。", let before, before.marked == nil else {
      reset()
      ordinaryInsert()
      return false
    }
    eligible = false
    let identity = ObjectIdentifier(client as AnyObject)
    if target != identity || expected?.matches(before) != true {
      reset()
    }
    if count == 2, before.location >= 2, before.before.hasSuffix("。。") {
      reset()
      client.insertText("...", replacementRange: NSRange(location: before.location - 2, length: 2))
      return true
    }
    let previousCount = count
    let insertionGeneration = generation
    ordinaryInsert()
    guard generation == insertionGeneration else { return false }
    let after = InputContextProbe.snapshot(client: client)
    // Synchronous client calls can reenter lifecycle callbacks even while
    // reading the post-insert snapshot; never restore invalidated state.
    guard generation == insertionGeneration else { return false }
    guard let after, after.marked == nil,
      after.location == before.location + 1,
      after.before == InputContinuityTracker.suffix(before.before + text)
    else { reset(); return false }
    count = previousCount + 1
    expected = after
    target = identity
    return false
  }
}
