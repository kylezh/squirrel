import InputMethodKit

@main
struct PeriodTests {
  static func main() {
    setbuf(stdout, nil)
    _ = NSApplication.shared
    var failures = 0
    func run(_ name: String, expected: String, _ body: (Harness) -> Void) {
      let h = Harness()
      body(h)
      if h.client.view.string != expected {
        print("FAIL \(name): \(h.client.view.string.debugDescription) != \(expected.debugDescription)")
        failures += 1
      } else { print("PASS \(name)") }
    }
    run("first is immediate", expected: "。") { $0.dot() }
    run("second is immediate", expected: "。。") { $0.dot(); $0.dot() }
    run("third replaces two committed periods", expected: "...") { $0.dots(3) }
    run("six dots", expected: "......") { $0.dots(6) }
    run("UTF16 replacement after emoji", expected: "😀中文...") { h in
      h.client.insertText("😀中文", replacementRange: .init(location: NSNotFound, length: 0))
      h.dots(3)
    }
    run("unrelated existing periods", expected: "。。...") { h in
      h.client.insertText("。。", replacementRange: .init(location: NSNotFound, length: 0))
      h.dots(3)
    }
    run("other key resets", expected: "。。a。") { h in
      h.dots(2); h.prepare("a"); h.client.insertText("a", replacementRange: .init(location: NSNotFound, length: 0)); h.dot()
    }
    run("newline resets", expected: "。。\n。") { h in
      h.dots(2); h.prepare("\r", code: 36); h.client.insertText("\n", replacementRange: .init(location: NSNotFound, length: 0)); h.dot()
    }
    run("backspace resets", expected: "。。") { h in
      h.dots(2); h.prepare("\u{7f}", code: 51); h.client.view.deleteBackward(nil); h.dot()
    }
    run("modifier resets", expected: "。。。") { h in
      h.dots(2); h.prepare("", type: .flagsChanged, flags: .shift); h.dot()
    }
    for reason in [InputContinuityTracker.Reason.pointer, .focus, .schema] {
      run("lifecycle reset \(reason)", expected: "。。。") { h in
        h.dots(2); h.spacing.invalidate(reason); h.dot()
      }
    }
    run("suspend resets", expected: "。。。") { h in
      h.dots(2); h.spacing.suspend(); h.dot()
    }
    run("activation resets", expected: "。。。") { h in
      h.dots(2); h.spacing.activate(session: 2, client: h.client, mode: .verified); h.dot()
    }
    run("caret moved before previous dots", expected: "。。。。") { h in
      h.dots(2); h.client.view.setSelectedRange(.init(location: 0, length: 0)); h.dot()
      h.client.view.setSelectedRange(.init(location: 3, length: 0)); h.dot()
    }
    run("nonempty selection is not a retroactive replacement", expected: "。。") { h in
      h.dots(2); h.client.view.setSelectedRange(.init(location: 0, length: 1)); h.dot()
    }
    run("unavailable context", expected: "。。。") { h in
      h.client.unavailable = true; h.dots(3)
    }
    run("stale post-insert context", expected: "。。。") { h in
      h.client.delaySnapshotAfterInsert = true; h.dots(3)
    }
    run("feature disabled", expected: "。。。") { h in h.enabled = false; h.dots(3) }
    run("candidate composition excluded", expected: "。。。") { h in h.composing = true; h.dots(3) }
    run("ASCII excluded", expected: "...") { h in h.ascii = true; h.dots(3, text: ".") }
    run("nonperiod commit resets", expected: "。。X。") { h in
      h.dots(2); h.dot(text: "X"); h.dot()
    }
    run("reset during insert is not overwritten", expected: "。。。") { h in
      h.dot(); h.dot(duringInsert: { h.sequence.reset() }); h.dot()
    }
    run("client identity changes", expected: "。。") { h in
      h.dots(2)
      let other = TextClient()
      other.insertText("。。", replacementRange: .init(location: NSNotFound, length: 0))
      h.prepare(".")
      h.sequence.insert("。", before: InputContextProbe.snapshot(client: other), client: other) {
        other.insertText("。", replacementRange: .init(location: NSNotFound, length: 0))
      }
      if other.view.string != "。。。" { failures += 1; print("FAIL other client overwritten") }
    }
    run("event fallback first immediate", expected: "。") { h in h.fallback = true; h.dot() }
    run("event fallback second immediate", expected: "。。") { h in h.fallback = true; h.dots(2) }
    run("event fallback third", expected: "...") { h in h.fallback = true; h.dots(3) }
    run("event fallback six", expected: "......") { h in h.fallback = true; h.dots(6) }
    run("event fallback emission failure", expected: "。。。") { h in
      h.fallback = true; h.emissionAllowed = false; h.dots(3)
    }
    run("event fallback other key", expected: "。。。") { h in
      h.fallback = true; h.dots(2); h.prepare("a"); h.dot()
    }
    run("event fallback modifiers", expected: "。。。") { h in
      h.fallback = true; h.dots(2); h.prepare("", type: .flagsChanged, flags: .control); h.dot()
    }
    for reason in [InputContinuityTracker.Reason.pointer, .focus, .schema, .edit] {
      run("event fallback reset \(reason)", expected: "。。。") { h in
        h.fallback = true; h.dots(2); h.spacing.invalidate(reason); h.dot()
      }
    }
    run("event fallback reentrant reset", expected: "。。。") { h in
      h.fallback = true; h.dot(); h.dot(duringInsert: { h.sequence.reset() }); h.dot()
    }
    run("event fallback disabled", expected: "。。。") { h in
      h.fallback = true; h.enabled = false; h.dots(3)
    }
    run("event fallback composing", expected: "。。。") { h in
      h.fallback = true; h.composing = true; h.dots(3)
    }
    run("event fallback does not inherit verified count", expected: "。。。") { h in
      h.dots(2); h.fallback = true; h.dot()
    }
    run("event fallback failure starts a fresh sequence", expected: "。。。...") { h in
      h.fallback = true; h.emissionAllowed = false; h.dots(3)
      h.emissionAllowed = true; h.dots(3)
    }
    run("event fallback reset during emission", expected: "...。") { h in
      h.fallback = true; h.duringEmission = { h.sequence.reset() }; h.dots(4)
    }
    run("event fallback does not inherit another client", expected: "。。") { h in
      h.fallback = true; h.dots(2)
      let other = TextClient()
      h.prepare(".")
      h.sequence.insert("。", before: nil, client: other, eventFallback: {
        failures += 1; print("FAIL erased other client"); return true
      }) { other.insertText("。", replacementRange: .init(location: NSNotFound, length: 0)) }
    }
    let events = GhosttyPeriodKeys.events()
    let codes: [Int64] = [51, 51, 51, 51, 47, 47, 47, 47, 47, 47]
    if events?.map({ $0.getIntegerValueField(.keyboardEventKeycode) }) != codes {
      failures += 1; print("FAIL ordered two backspaces and three periods")
    }
    if let events {
      for (index, event) in events.enumerated() {
        let expectedType: CGEventType = index.isMultiple(of: 2) ? .keyDown : .keyUp
        if event.type != expectedType || !event.flags.isEmpty || !GhosttyPeriodKeys.isSynthetic(event) {
          failures += 1; print("FAIL event type, modifiers or marker")
        }
        if let bridged = NSEvent(cgEvent: event)?.cgEvent {
          if !GhosttyPeriodKeys.isSynthetic(bridged) { failures += 1; print("FAIL NSEvent marker bridge") }
        } else { failures += 1; print("FAIL NSEvent bridge") }
        if index >= 4 {
          var units = [UniChar](repeating: 0, count: 8), length = 0
          event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
          if Array(units.prefix(length)) != [46] { failures += 1; print("FAIL ASCII period payload") }
        }
      }
    }
    assert(failures == 0, "\(failures) period failures")
  }

  final class Harness {
    let client = TextClient()
    let sequence = PeriodSequence()
    var enabled = true, composing = false, ascii = false
    var fallback = false, emissionAllowed = true
    var duringEmission: () -> Void = {}
    lazy var spacing = SpacingContext(onReset: { [weak self] in self?.sequence.reset() }) { _ in }
    init() { spacing.activate(session: 1, client: client, mode: .verified) }
    func prepare(_ text: String, code: UInt16 = 47, type: NSEvent.EventType = .keyDown,
                 flags: NSEvent.ModifierFlags = []) {
      let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: text,
        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
      sequence.prepare(event, enabled: enabled, composing: composing, ascii: ascii)
    }
    func dot(text: String = "。", duringInsert: () -> Void = {}) {
      prepare(".")
      sequence.insert(text, before: fallback ? nil : InputContextProbe.snapshot(client: client), client: client,
                      eventFallback: fallback ? { [self] in
        guard emissionAllowed else { return false }
        duringEmission()
        client.view.deleteBackward(nil); client.view.deleteBackward(nil)
        client.insertText("...", replacementRange: .init(location: NSNotFound, length: 0))
        return true
      } : nil) {
        client.insertText(text, replacementRange: .init(location: NSNotFound, length: 0))
        duringInsert()
      }
    }
    func dots(_ count: Int, text: String = "。") { for _ in 0..<count { dot(text: text) } }
  }
}
