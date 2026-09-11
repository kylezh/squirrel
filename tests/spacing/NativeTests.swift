import InputMethodKit

@main
struct NativeTests {
  static func main() {
    _ = NSApplication.shared
    let client = TextClient()
    var messages: [String] = []
    let context = SpacingContext { messages.append($0) }
    func state() -> String { messages.last!.split(separator: "|").last.map(String.init)! }
    func epoch() -> String { String(messages.last!.split(separator: "|")[2]) }
    func commit(_ text: String) {
      let before = context.beforeCommit(client: client)
      client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
      context.didCommit(text, before: before, client: client)
    }
    context.activate(session: 1, client: client, mode: .verified)
    context.prepare(client: client)
    assert(state() == "empty")
    commit("中文")
    assert(state() == "tracking")
    let oldEpoch = epoch()
    client.setMarkedText(
      "hello", selectionRange: NSRange(location: 5, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    context.prepare(client: client)
    assert(state() == "tracking" && epoch() == oldEpoch, "marked text must preserve anchor")
    commit(" hello")
    assert(client.view.string == "中文 hello" && state() == "tracking")
    client.view.setSelectedRange(NSRange(location: 0, length: 0))
    context.prepare(client: client)
    assert(state() == "empty" && epoch() != oldEpoch)
    commit("new")
    client.view.setSelectedRange(NSRange(location: 0, length: 3))
    context.prepare(client: client)
    assert(state() == "uncertain", "replacement selection cannot reuse a boundary")
    client.view.setSelectedRange(NSRange(location: 3, length: 0))
    context.prepare(client: client)
    commit("text")
    let copyEpoch = epoch()
    let copy = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c",
      isARepeat: false, keyCode: 8)!
    context.beforeKey(copy, client: client, composing: false)
    context.afterKey(copy, handled: false, client: client)
    assert(epoch() == copyEpoch && state() == "tracking", "copy preserves state")
    let paste = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v",
      isARepeat: false, keyCode: 9)!
    context.beforeKey(paste, client: client, composing: false)
    context.afterKey(paste, handled: false, client: client)
    assert(epoch() != copyEpoch && state() == "empty")
    context.prepare(client: client)
    let rawBefore = context.beforeCommit(client: client)
    client.insertText("raw", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    context.didCommit("raw", before: rawBefore, client: client, observed: false)
    assert(state() == "empty", "unobserved direct commits must invalidate Lua boundary")
    client.unavailable = true
    context.prepare(client: client)
    assert(state() == "uncertain")
    context.suspend()
    commit("teardown")
    assert(state() == "suspended")
    context.activate(session: 2, client: client, mode: .eventsOnly)
    context.prepare(client: client)
    commit("compatibility")
    assert(state() == "tracking")
    context.suspend()
    print(
      "PASS: native NSTextView selection, marked text, commit confirmation, shortcuts, unsupported clients, teardown"
    )
  }
}
