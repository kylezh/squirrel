import InputMethodKit

// NSTextView supplies real marked-text and selection behavior. Geometry and
// IMK registration are outside this in-process integration harness.
final class TextClient: NSObject, IMKTextInput {
  let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
  var unavailable = false
  // Ghostty 1.3.1 exposes terminal selection, not the insertion position.
  var terminalSelectionOnly = false
  func insertText(_ string: Any!, replacementRange: NSRange) {
    view.insertText(string!, replacementRange: replacementRange)
  }
  func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
    view.setMarkedText(string!, selectedRange: selectionRange, replacementRange: replacementRange)
  }
  func selectedRange() -> NSRange {
    if terminalSelectionOnly { return NSRange(location: 0, length: 0) }
    return unavailable ? NSRange(location: NSNotFound, length: NSNotFound) : view.selectedRange()
  }
  func markedRange() -> NSRange {
    let range = view.markedRange()
    if terminalSelectionOnly {
      return NSRange(location: 0, length: range.location == NSNotFound ? 0 : range.length)
    }
    return range
  }
  func attributedSubstring(from range: NSRange) -> NSAttributedString! {
    unavailable || terminalSelectionOnly
      ? nil : view.attributedSubstring(forProposedRange: range, actualRange: nil)
  }
  func length() -> Int { view.string.utf16.count }
  func characterIndex(
    for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode,
    inMarkedRange: UnsafeMutablePointer<ObjCBool>!
  ) -> Int { NSNotFound }
  func attributes(forCharacterIndex index: Int, lineHeightRectangle: UnsafeMutablePointer<NSRect>!)
    -> [AnyHashable: Any]!
  { [:] }
  func validAttributesForMarkedText() -> [Any]! { [] }
  func overrideKeyboard(withKeyboardNamed name: String!) {}
  func selectMode(_ identifier: String!) {}
  func supportsUnicode() -> Bool { true }
  func bundleIdentifier() -> String! { "org.rime.spacing.test" }
  func windowLevel() -> CGWindowLevel { 0 }
  func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
  func uniqueClientIdentifierString() -> String! { "test-client" }
  func string(from range: NSRange, actualRange: NSRangePointer!) -> String! {
    attributedSubstring(from: range)?.string
  }
  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}
