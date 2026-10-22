import Foundation

@main
struct DictionaryTests {
  static func check(_ condition: @autoclosure () throws -> Bool) rethrows {
    let result = try condition()
    assert(result)
  }

  static func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let store = DictionaryStore(root: root)
    let base = "---\nname: rime_ice\nversion: '1'\nimport_tables:\n  - cn_dicts/base\n...\n"
    try Data(base.utf8).write(to: root.appendingPathComponent("rime_ice.dict.yaml"))
    try fm.createDirectory(at: root.appendingPathComponent("cn_dicts"), withIntermediateDirectories: true)
    let original = Data("---\nname: base\nversion: '1'\n...\n你好\tni hao\n".utf8)
    try original.write(to: root.appendingPathComponent("cn_dicts/base.dict.yaml"))
    try Data("personal".utf8).write(to: root.appendingPathComponent("custom_phrase.txt"))
    let imported = fm.temporaryDirectory.appendingPathComponent("personal-\(UUID().uuidString).dict.yaml")
    defer { try? fm.removeItem(at: imported) }
    try Data("---\nname: personal\nversion: '1'\n...\n测试\tce shi\n".utf8).write(to: imported)
    try store.importDictionary(from: imported)
    try check(try store.entries().contains { $0.path == "personal.dict.yaml" && $0.removable })
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice.dict.yaml"), encoding: .utf8).contains("  - 'personal'\n"))
    do { try store.importDictionary(from: imported); assertionFailure("duplicate accepted") } catch {}
    let dependent = root.appendingPathComponent("dependent.dict.yaml")
    try Data("---\nname: dependent\nversion: '1'\nimport_tables:\n  - personal\n...\n".utf8).write(to: dependent)
    do { try store.removeDictionary(path: "personal.dict.yaml"); assertionFailure("referenced dictionary removed") } catch {}
    try fm.removeItem(at: dependent)
    try store.removeDictionary(path: "personal.dict.yaml")
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice.dict.yaml"), encoding: .utf8) == base)
    do { try store.removeDictionary(path: "cn_dicts/base.dict.yaml"); assertionFailure("base removed") } catch {}
    do { try store.installUpdates(["cn_dicts/base.dict.yaml": Data("<html>error</html>".utf8)]); assertionFailure("invalid update") } catch {}
    try check(try Data(contentsOf: root.appendingPathComponent("cn_dicts/base.dict.yaml")) == original)
    do { try store.installUpdates(["../escape.dict.yaml": original]); assertionFailure("unsafe path") } catch {}
    let updated = Data("---\nname: base\nversion: '2'\n...\n更新\tgeng xin\n".utf8)
    try store.installUpdates(["cn_dicts/base.dict.yaml": updated])
    try check(try Data(contentsOf: root.appendingPathComponent("cn_dicts/base.dict.yaml")) == updated)
    try check(try String(contentsOf: root.appendingPathComponent("custom_phrase.txt"), encoding: .utf8) == "personal")
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice.dict.yaml"), encoding: .utf8) == base)
    // Simulate disk failure after the first replacement, then verify full rollback.
    var writes = 0
    let failing = DictionaryStore(root: root, writeFile: { data, url in
      writes += 1
      if writes == 2 { throw DictionaryFailure(message: "simulated disk failure") }
      try data.write(to: url, options: .atomic)
    })
    do { try failing.importDictionary(from: imported); assertionFailure("write failure ignored") } catch {}
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice.dict.yaml"), encoding: .utf8) == base)
    assert(!fm.fileExists(atPath: root.appendingPathComponent("personal.dict.yaml").path))
    try check(try store.entries().allSatisfy { !$0.removable })
    try Data("---\nname:\n...\n".utf8).write(to: imported)
    do { try store.importDictionary(from: imported); assertionFailure("empty name accepted") } catch {}
    try Data("---\nname: invalid\nversion: '1'\nbroken: [\n...\n".utf8).write(to: imported)
    do { try store.importDictionary(from: imported); assertionFailure("malformed YAML accepted") } catch {}
    try Data("---\nname: invalid\nversion: '1'\nimport_tables:\n  - missing_dictionary\n...\n".utf8).write(to: imported)
    do { try store.importDictionary(from: imported); assertionFailure("missing dependency accepted") } catch {}
    try Data("---\nname: missing_version\n...\n词\tci\n".utf8).write(to: imported)
    do { try store.importDictionary(from: imported); assertionFailure("missing version accepted") } catch {}
    try Data("---\nname: circular\nversion: '1'\nimport_tables:\n  - rime_ice\n...\n".utf8).write(to: imported)
    do { try store.importDictionary(from: imported); assertionFailure("cycle accepted") } catch {}
    try Data("---\nname: 'null'\nversion: '1'\n...\n词\tci\n".utf8).write(to: imported)
    try store.importDictionary(from: imported)
    let mainText = try String(contentsOf: root.appendingPathComponent("rime_ice.dict.yaml"), encoding: .utf8)
    var parsed = RimeConfig()
    let api = rime_get_api_stdbool().pointee
    assert(api.config_load_string(&parsed, mainText))
    assert(api.config_get_cstring(&parsed, "import_tables/@0") != nil, "reference must be a YAML string")
    _ = api.config_close(&parsed)
    try store.removeDictionary(path: "null.dict.yaml")
    // Restoration of one file must continue even when another restoration fails.
    for name in ["ext", "others"] {
      try original.write(to: root.appendingPathComponent("cn_dicts/\(name).dict.yaml"))
    }
    var attempts = 0
    let brokenDisk = DictionaryStore(root: root, writeFile: { data, url in
      attempts += 1
      if url.lastPathComponent == "others.dict.yaml" || (attempts > 3 && url.lastPathComponent == "ext.dict.yaml") {
        throw DictionaryFailure(message: "persistent disk failure")
      }
      try data.write(to: url, options: .atomic)
    })
    do {
      try brokenDisk.installUpdates(["cn_dicts/base.dict.yaml": original, "cn_dicts/ext.dict.yaml": updated,
                                     "cn_dicts/others.dict.yaml": updated])
      assertionFailure("persistent failure ignored")
    } catch {
      assert(error.localizedDescription.contains("备份："))
    }
    try check(try Data(contentsOf: root.appendingPathComponent("cn_dicts/base.dict.yaml")) == updated)
    assert(attempts == 5, "rollback must attempt every changed path")
    let stateBefore = DictionaryUpdateState(enabled: true)
    try store.saveState(stateBefore)
    try check(try store.loadState().enabled)
    // A personal entry point must receive imports directly (Rime does not recurse import_tables).
    try fm.createDirectory(at: root.appendingPathComponent("build"), withIntermediateDirectories: true)
    try Data("translator:\n  dictionary: rime_ice_personal\n".utf8).write(to: root.appendingPathComponent("build/rime_ice.schema.yaml"))
    let personal = "---\nname: rime_ice_personal\nversion: '1'\nimport_tables:\n  - rime_ice\n...\n"
    try Data(personal.utf8).write(to: root.appendingPathComponent("rime_ice_personal.dict.yaml"))
    try Data("---\nname: extra\nversion: '1'\n...\n词\tci\n".utf8).write(to: imported)
    try store.importDictionary(from: imported)
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice_personal.dict.yaml"), encoding: .utf8).contains("  - 'extra'\n"))
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice.dict.yaml"), encoding: .utf8) == base)
    try store.removeDictionary(path: "extra.dict.yaml")
    try check(try String(contentsOf: root.appendingPathComponent("rime_ice_personal.dict.yaml"), encoding: .utf8) == personal)
    var state = DictionaryUpdateState()
    let now = Date()
    assert(!state.isDue(at: now))
    state.enabled = true
    assert(state.isDue(at: now))
    state.lastSuccess = now
    assert(!state.isDue(at: now.addingTimeInterval(6 * 86400)))
    assert(state.isDue(at: now.addingTimeInterval(7 * 86400)))
    state.lastAttempt = now.addingTimeInterval(7 * 86400)
    assert(!state.isDue(at: now.addingTimeInterval(7 * 86400 + 60)))
    print("Dictionary tests passed")
  }
}
