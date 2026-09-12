import InputMethodKit

// Ghostty's terminal selection is not a document insertion range. This optional
// fallback sends real keys to its process, never control bytes through paste.
struct GhosttyPeriodKeys {
  static let bundleIdentifier = "com.mitchellh.ghostty"
  private static let marker: Int64 = 0x5351504552494F44

  static func isSynthetic(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == marker
  }

  static func events() -> [CGEvent]? {
    guard let source = CGEventSource(stateID: .privateState) else { return nil }
    var result: [CGEvent] = []
    for code: CGKeyCode in [51, 51, 47, 47, 47] {
      for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        else { return nil }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        if code == 47 {
          var dot: UniChar = 46
          event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &dot)
        }
        result.append(event)
      }
    }
    return result
  }

  static func post() -> Bool {
    guard CGPreflightPostEventAccess(),
      let app = NSWorkspace.shared.frontmostApplication,
      app.bundleIdentifier == bundleIdentifier,
      let batch = events(),
      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    else { return false }
    // Construct and validate everything before posting anything. Do not mix
    // asynchronous key posts with a synchronous IMK insertText for the dots.
    // OS delivery is ordered submission, not an atomic terminal transaction.
    for event in batch { event.postToPid(app.processIdentifier) }
    return true
  }
}
