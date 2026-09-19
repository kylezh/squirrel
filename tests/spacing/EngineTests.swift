import InputMethodKit

@main
struct EngineTests {
  static func main() {
    setbuf(stdout, nil)
    _ = NSApplication.shared
    let root = CommandLine.arguments[1]
    guard dlopen(root + "/lib/rime-plugins/librime-lua.dylib", RTLD_NOW | RTLD_GLOBAL) != nil else {
      fatalError("lua plugin missing")
    }
    let api = rime_get_api_stdbool().pointee
    var traits = RimeTraits.rimeStructInit()
    traits.setCString(root + "/build/spacing/test-data", to: \.user_data_dir)
    traits.setCString(root + "/build/spacing/test-data", to: \.shared_data_dir)
    traits.setCString("rime.spacing-tests", to: \.app_name)
    traits.min_log_level = 2
    let names: [String] = ["default", "lua"]
    var modules: [UnsafePointer<CChar>?] =
      names.map { name in UnsafePointer<CChar>(strdup(name)) } + [nil]
    modules.withUnsafeMutableBufferPointer { ptr in
      traits.modules = ptr.baseAddress
      api.setup(&traits)
      api.initialize(&traits)
    }
    defer { api.finalize() }
    var failures = 0
    func run(_ name: String, expected: String, body: (Harness) -> Void) {
      let h = Harness(api: api)
      body(h)
      if h.client.view.string != expected {
        print(
          "FAIL \(name): \(h.client.view.string.debugDescription) != \(expected.debugDescription)")
        failures += 1
      } else {
        print("PASS \(name)")
      }
    }
    run("English Chinese", expected: "hello 中文") { h in
      h.mode(true)
      h.type("hello")
      h.mode(false)
      h.type("zhongwen ")
    }
    run("Chinese English", expected: "中文 hello") { h in
      h.type("zhongwen ")
      h.mode(true)
      h.type("hello")
    }
    run("alternating", expected: "中文 hello 中文") { h in
      h.type("zhongwen ")
      h.mode(true)
      h.type("hello")
      h.mode(false)
      h.type("zhongwen ")
    }
    run("newline", expected: "中文\nhello") { h in
      h.type("zhongwen ")
      h.key("\r", code: 36, rime: 0xff0d)
      h.mode(true)
      h.type("hello")
    }
    run("Shift newline", expected: "中文\nhello") { h in
      h.type("zhongwen ")
      h.key("\r", code: 36, rime: 0xff0d, flags: .shift)
      h.mode(true)
      h.type("hello")
    }
    run("mouse replacement", expected: "hello中文") { h in
      h.type("zhongwen ")
      h.spacing.invalidate(.pointer)
      h.client.view.setSelectedRange(NSRange(location: 0, length: 0))
      h.mode(true)
      h.type("hello")
    }
    run("unobserved direct commit", expected: "hello中文中文") { h in
      h.mode(true)
      h.type("hello")
      h.key("[", code: 33, rime: 91)
      h.mode(false)
      h.type("zhongwen ")
    }
    run("Chinese digit passthrough", expected: "中文 0123456789 中文") { h in
      h.type("zhongwen 0123456789zhongwen ")
    }
    run("Chinese ASCII digits", expected: "中文 123 中文") { h in
      h.type("zhongwen ")
      h.mode(true)
      h.type("123")
      h.mode(false)
      h.type("zhongwen ")
    }
    run("alphanumeric and decimal spacing", expected: "中文 A100 3.14 中文") { h in
      h.type("zhongwen ")
      h.mode(true)
      h.type("A100 3.14")
      h.mode(false)
      h.type("zhongwen ")
    }
    run("digit selection then English", expected: "中文 hello") { h in
      h.type("zhongwen1")
      h.mode(true)
      h.type("hello")
    }
    run("digit selection then raw digit", expected: "中文 2") { h in
      h.type("zhongwen12")
    }
    run("existing space before digits", expected: "中文 123") { h in
      h.type("zhongwen  123")
    }
    run("newline before digits", expected: "中文\n123") { h in
      h.type("zhongwen ")
      h.key("\r", code: 36, rime: 0xff0d)
      h.type("123")
    }
    run("number selection", expected: "hello 中文") { h in
      h.mode(true)
      h.type("hello")
      h.mode(false)
      h.type("zhongwen1")
    }
    run("mouse candidate selection", expected: "hello 中文") { h in
      h.mode(true)
      h.type("hello")
      h.mode(false)
      h.type("zhongwen")
      h.spacing.prepare(client: h.client)
      assert(h.api.select_candidate(h.session, 0))
      h.update()
    }
    run("copy", expected: "中文 hello") { h in
      h.type("zhongwen ")
      h.key("c", code: 8, rime: 99, flags: .command)
      h.mode(true)
      h.type("hello")
    }
    run("existing space", expected: "中文 hello") { h in
      h.type("zhongwen ")
      h.type(" ")
      h.mode(true)
      h.type("hello")
    }
    run("Return raw English", expected: "中文 hello") { h in
      h.type("zhongwen hello")
      h.key("\r", code: 36, rime: 0xff0d)
    }
    func adaptive(_ h: Harness) {
      h.spacing.activate(
        session: h.session, client: h.client,
        mode: InputContinuityTracker.Mode(rawValue: "adaptive") ?? .verified)
      h.client.unavailable = true
    }
    run("adaptive unavailable alternating", expected: "中文 hello 中文") { h in
      adaptive(h)
      h.type("zhongwen ")
      h.mode(true)
      h.type("hello")
      h.mode(false)
      h.type("zhongwen ")
    }
    run("adaptive newline", expected: "中文\nhello") { h in
      adaptive(h)
      h.type("zhongwen ")
      h.key("\r", code: 36, rime: 0xff0d)
      h.mode(true)
      h.type("hello")
    }
    run("adaptive pointer", expected: "中文hello") { h in
      adaptive(h)
      h.type("zhongwen ")
      h.spacing.invalidate(.pointer)
      h.mode(true)
      h.type("hello")
    }
    run("adaptive query recovery", expected: "中文 hello 中文") { h in
      adaptive(h)
      h.type("zhongwen ")
      h.client.unavailable = false
      h.mode(true)
      h.type("hello")
      h.client.unavailable = true
      h.mode(false)
      h.type("zhongwen ")
    }
    run("adaptive readable selection", expected: "中hello") { h in
      adaptive(h)
      h.client.unavailable = false
      h.type("zhongwen ")
      h.client.view.setSelectedRange(NSRange(location: 1, length: 1))
      h.mode(true)
      h.type("hello")
    }
    func delayedReturn(_ h: Harness, mode: InputContinuityTracker.Mode) {
      h.spacing.activate(session: h.session, client: h.client, mode: mode)
      h.client.delaySnapshotAfterInsert = true
      h.type("tos")
      h.key("\r", code: 36, rime: 0xff0d)
      h.client.refreshSnapshot()
      h.client.delaySnapshotAfterInsert = false
    }
    run("delayed snapshot reproduces missing boundary in adaptive mode", expected: "tos中文") { h in
      delayedReturn(h, mode: .adaptive)
      h.type("zhongwen ")
    }
    run("events-only preserves Return boundary with delayed snapshot", expected: "tos 中文") { h in
      delayedReturn(h, mode: .eventsOnly)
      h.type("zhongwen ")
    }
    run("events-only resets real newline after Return commit", expected: "tos\n中文") { h in
      delayedReturn(h, mode: .eventsOnly)
      h.key("\r", code: 36, rime: 0xff0d)
      h.type("zhongwen ")
    }
    run("events-only resets pointer after Return commit", expected: "tos中文") { h in
      delayedReturn(h, mode: .eventsOnly)
      h.spacing.invalidate(.pointer)
      h.type("zhongwen ")
    }
    // Models an editor whose document query still describes the old composition
    // after Chinese commit. This is not a captured Google Docs client trace.
    func delayedChinese(_ h: Harness, mode: InputContinuityTracker.Mode) {
      h.spacing.activate(session: h.session, client: h.client, mode: mode)
      h.client.delaySnapshotAfterInsert = true
      h.type("zhongwen ")
      h.client.refreshSnapshot()
      h.client.delaySnapshotAfterInsert = false
    }
    run("delayed Chinese then raw ni loses adaptive boundary", expected: "中文ni") { h in
      delayedChinese(h, mode: .adaptive)
      h.type("ni")
      h.key("\r", code: 36, rime: 0xff0d)
    }
    run("events-only preserves Chinese then raw ni", expected: "中文 ni") { h in
      delayedChinese(h, mode: .eventsOnly)
      h.type("ni")
      h.key("\r", code: 36, rime: 0xff0d)
    }
    run("events-only resets newline before raw ni", expected: "中文\nni") { h in
      delayedChinese(h, mode: .eventsOnly)
      h.key("\r", code: 36, rime: 0xff0d)
      h.type("ni")
      h.key("\r", code: 36, rime: 0xff0d)
    }
    run("events-only resets pointer before raw ni", expected: "中文ni") { h in
      delayedChinese(h, mode: .eventsOnly)
      h.spacing.invalidate(.pointer)
      h.type("ni")
      h.key("\r", code: 36, rime: 0xff0d)
    }
    func ghostty(_ h: Harness) {
      h.client.terminalSelectionOnly = true
      h.spacing.activate(session: h.session, client: h.client, mode: .eventsOnly)
    }
    run("Ghostty digit selection then English", expected: "中文 hello") { h in
      ghostty(h)
      h.type("zhongwen1")
      h.mode(true)
      h.type("hello")
    }
    run("Ghostty digit selection then raw digit", expected: "中文 2") { h in
      ghostty(h)
      h.type("zhongwen12")
    }
    run("Ghostty digit passthrough", expected: "中文 123 中文") { h in
      ghostty(h)
      h.type("zhongwen 123zhongwen ")
    }
    run("Ghostty digits after pointer reset", expected: "中文123") { h in
      ghostty(h)
      h.type("zhongwen ")
      h.spacing.invalidate(.pointer)
      h.type("123")
    }
    run("Ghostty digits after newline", expected: "中文\n123") { h in
      ghostty(h)
      h.type("zhongwen ")
      h.key("\r", code: 36, rime: 0xff0d)
      h.type("123")
    }
    run("Ghostty selection-only alternating", expected: "中文 hello 中文") { h in
      ghostty(h)
      h.type("zhongwen ")
      h.mode(true)
      h.type("hello")
      h.mode(false)
      h.type("zhongwen ")
    }
    run("Ghostty selection-only newline", expected: "中文\nhello") { h in
      ghostty(h)
      h.type("zhongwen ")
      h.key("\r", code: 36, rime: 0xff0d)
      h.mode(true)
      h.type("hello")
    }
    run("Ghostty selection-only pointer reset", expected: "中文hello") { h in
      ghostty(h)
      h.type("zhongwen ")
      h.spacing.invalidate(.pointer)
      h.mode(true)
      h.type("hello")
    }
    func runPeriods(_ name: String, expected: String, body: (Harness) -> Void) {
      let h = Harness(api: api, schema: "spacing_test_period")
      h.periodsEnabled = true
      body(h)
      if h.client.view.string != expected {
        print("FAIL \(name): \(h.client.view.string.debugDescription) != \(expected.debugDescription)")
        failures += 1
      } else { print("PASS \(name)") }
    }
    runPeriods("immediate native period", expected: "中文。") { h in h.type("zhongwen .") }
    runPeriods("native third period replacement", expected: "中文...") { h in h.type("zhongwen ...") }
    runPeriods("replacement then English spacing", expected: "中文...hello 中文") { h in
      h.type("zhongwen ..."); h.mode(true); h.type("hello"); h.mode(false); h.type("zhongwen ")
    }
    runPeriods("marked-text compatibility replacement", expected: "中文...") { h in
      h.forceMarkedText = true; h.type("zhongwen ...")
    }
    runPeriods("numeric period unchanged", expected: "1.2") { h in h.type("1.2") }
    for digit in 0...9 {
      runPeriods("Chinese then single digit decimal \(digit)", expected: "中文 \(digit).4") { h in
        h.type("zhongwen \(digit).4")
      }
    }
    runPeriods("digit-selected Chinese then decimal", expected: "中文 5.4") { h in
      h.type("zhongwen15.4")
    }
    runPeriods("explicit space before decimal", expected: "中文 5.4") { h in
      h.type("zhongwen  5.4")
    }
    runPeriods("multi-digit decimal after Chinese", expected: "中文 15.4") { h in
      h.type("zhongwen 15.4")
    }
    for (input, expected) in [("5,400", "中文 5,400"), ("5:40", "中文 5:40")] {
      runPeriods("numeric separator after automatic space: \(input)", expected: expected) { h in
        h.type("zhongwen " + input)
      }
    }
    for mode in [InputContinuityTracker.Mode.adaptive, .eventsOnly] {
      runPeriods("Chinese then decimal in \(mode)", expected: "中文 5.4") { h in
        h.spacing.activate(session: h.session, client: h.client, mode: mode)
        h.client.terminalSelectionOnly = mode == .eventsOnly
        h.type("zhongwen 5.4")
      }
    }
    runPeriods("ASCII periods unchanged", expected: "...") { h in h.mode(true); h.type("...") }
    runPeriods("paging remains composing", expected: "zhong wen") { h in
      h.type("zhongwen...")
      if h.api.get_input(h.session).map({ String(cString: $0) }) != "zhongwen" {
        print("FAIL paging period entered or committed input"); failures += 1
      }
    }
    runPeriods("native pointer reset", expected: "中文。。。") { h in
      h.type("zhongwen .."); h.spacing.invalidate(.pointer); h.type(".")
    }
    runPeriods("native events-only fallback", expected: "中文。。。") { h in
      h.spacing.activate(session: h.session, client: h.client, mode: .eventsOnly)
      h.periodsEnabled = false
      h.client.terminalSelectionOnly = true
      h.type("zhongwen ...")
    }
    assert(failures == 0, "\(failures) engine integration failures")
  }

  final class Harness {
    let api: RimeApi_stdbool
    let session: UInt
    let client = TextClient()
    let periods = PeriodSequence()
    var periodsEnabled = false
    var forceMarkedText = false
    lazy var spacing = SpacingContext(onReset: { [weak self] in self?.periods.reset() }) { [weak self] value in
      guard let self else { return }
      api.set_property(session, "squirrel_spacing_context", value)
    }
    init(api: RimeApi_stdbool, schema: String = "spacing_test") {
      self.api = api
      session = api.create_session()
      assert(session != 0)
      assert(api.select_schema(session, schema))
      spacing.activate(session: session, client: client, mode: .verified)
    }
    deinit {
      spacing.suspend()
      _ = api.destroy_session(session)
    }
    func mode(_ ascii: Bool) { api.set_option(session, "ascii_mode", ascii) }
    func type(_ text: String) {
      for scalar in text.unicodeScalars { key(String(scalar), code: 0, rime: Int32(scalar.value)) }
    }
    func key(_ text: String, code: UInt16, rime: Int32, flags: NSEvent.ModifierFlags = []) {
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
        context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false,
        keyCode: code)!
      let composing = api.get_input(session).map { $0.pointee != 0 } ?? false
      spacing.beforeKey(event, client: client, composing: composing)
      periods.prepare(event, enabled: periodsEnabled, composing: composing,
                      ascii: api.get_option(session, "ascii_mode") || api.get_option(session, "ascii_punct"))
      let handled =
        flags.contains(.command)
        ? false : api.process_key(session, rime, flags.contains(.shift) ? 1 : 0)
      update()
      spacing.afterKey(event, handled: handled, client: client)
      if !handled && !flags.contains(.command) {
        client.insertText(
          text == "\r" ? "\n" : text,
          replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
      }
    }
    func update() {
      var commit = RimeCommit.rimeStructInit()
      if api.get_commit(session, &commit) {
        let text = String(cString: commit.text)
        var receipt = [CChar](repeating: 0, count: 256)
        _ = api.get_property(session, "squirrel_spacing_receipt", &receipt, receipt.count)
        let observed = spacing.acceptsReceipt(String(cString: receipt), text: text)
        api.set_property(session, "squirrel_spacing_receipt", "")
        let before = spacing.beforeCommit(client: client)
        let replaced = periods.insert(text, before: before, client: client) {
          if forceMarkedText && !client.view.hasMarkedText() && !text.isEmpty {
            client.setMarkedText(text, selectionRange: .init(location: text.utf16.count, length: 0),
                                 replacementRange: .init(location: NSNotFound, length: 0))
          }
          client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
          spacing.didCommit(text, before: before, client: client, observed: observed)
        }
        if replaced { spacing.invalidate(.edit) }
        _ = api.free_commit(&commit)
      }
      var context = RimeContext_stdbool.rimeStructInit()
      if api.get_context(session, &context) {
        let preedit = context.composition.preedit.map { String(cString: $0) } ?? ""
        if !preedit.isEmpty {
          client.setMarkedText(
            preedit, selectionRange: NSRange(location: preedit.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
        _ = api.free_context(&context)
      }
    }
  }
}
