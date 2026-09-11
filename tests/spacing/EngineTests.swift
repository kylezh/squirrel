import InputMethodKit

@main
struct EngineTests {
  static func main() {
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
    func ghostty(_ h: Harness) {
      h.client.terminalSelectionOnly = true
      h.spacing.activate(session: h.session, client: h.client, mode: .eventsOnly)
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
    assert(failures == 0, "\(failures) engine integration failures")
  }

  final class Harness {
    let api: RimeApi_stdbool
    let session: UInt
    let client = TextClient()
    lazy var spacing = SpacingContext { [weak self] value in
      guard let self else { return }
      api.set_property(session, "squirrel_spacing_context", value)
    }
    init(api: RimeApi_stdbool) {
      self.api = api
      session = api.create_session()
      assert(session != 0)
      assert(api.select_schema(session, "spacing_test"))
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
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        spacing.didCommit(text, before: before, client: client, observed: observed)
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
