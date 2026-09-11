import Foundation

// The installer is compiled for its pure identity check; registration is never called.
enum SquirrelApp {
  static let appDir = URL(fileURLWithPath: "/unused")
}

@main
struct InputSourceTests {
  static func main() {
    let official = "im.rime.inputmethod.Squirrel"
    let development = official + ".SpacingDev"
    for bundle in [official, development] {
      for suffix in ["", ".Hans", ".Hant"] {
        assert(SquirrelInstaller.ownsInputSource(bundle + suffix, bundleIdentifier: bundle))
      }
      for other in ["", "com.apple.keylayout.ABC", bundle + ".Unknown"] {
        assert(!SquirrelInstaller.ownsInputSource(other, bundleIdentifier: bundle))
      }
    }
    for suffix in ["", ".Hans", ".Hant"] {
      assert(!SquirrelInstaller.ownsInputSource(official + suffix, bundleIdentifier: development))
      assert(!SquirrelInstaller.ownsInputSource(development + suffix, bundleIdentifier: official))
    }
    print("PASS: official and development input-source identities remain separate")
  }
}
