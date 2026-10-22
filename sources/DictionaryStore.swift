import Foundation

struct DictionaryUpdateState: Codable {
  var enabled = false
  var lastSuccess: Date?
  var lastAttempt: Date?
  var message = "尚未更新"

  func isDue(at date: Date) -> Bool {
    enabled && date.timeIntervalSince(lastSuccess ?? .distantPast) >= 7 * 86400
      && date.timeIntervalSince(lastAttempt ?? .distantPast) >= 6 * 3600
  }
}

struct DictionaryEntry {
  let path: String
  let removable: Bool
}

struct DictionaryFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// Only dictionary source files are changed. Learning databases and schema patches are never written.
final class DictionaryStore {
  let root: URL
  private let files = FileManager.default
  private let writeFile: (Data, URL) throws -> Void
  private var metadata: URL { root.appendingPathComponent(".squirrel-dictionaries") }
  private var importsURL: URL { metadata.appendingPathComponent("imports.json") }
  private var stateURL: URL { metadata.appendingPathComponent("state.json") }
  static let updatePaths = ["8105", "41448", "base", "ext", "tencent", "others"].map { "cn_dicts/\($0).dict.yaml" }
    + ["en", "en_ext"].map { "en_dicts/\($0).dict.yaml" }

  init(root: URL, writeFile: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
    self.root = root
    self.writeFile = writeFile
  }

  func loadState() throws -> DictionaryUpdateState {
    guard files.fileExists(atPath: stateURL.path) else { return DictionaryUpdateState() }
    return try JSONDecoder().decode(DictionaryUpdateState.self, from: Data(contentsOf: stateURL))
  }

  func saveState(_ state: DictionaryUpdateState) throws {
    try files.createDirectory(at: metadata, withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
  }

  private func imports() throws -> [String] {
    guard files.fileExists(atPath: importsURL.path) else { return [] }
    return try JSONDecoder().decode([String].self, from: Data(contentsOf: importsURL))
  }

  func entries() throws -> [DictionaryEntry] {
    let managed = try imports()
    var paths: [String] = []
    // Do not enumerate build, sync, backup, or user database directories.
    for directory in ["", "cn_dicts", "en_dicts"] {
      let url = root.appendingPathComponent(directory)
      guard files.fileExists(atPath: url.path) else { continue }
      for name in try files.contentsOfDirectory(atPath: url.path) where name.hasSuffix(".dict.yaml") {
        paths.append(directory.isEmpty ? name : directory + "/" + name)
      }
    }
    return paths.sorted().map { DictionaryEntry(path: $0, removable: managed.contains($0)) }
  }

  private func dictionaryName(_ data: Data, requireDependencies: Bool = false) throws -> String {
    guard let text = String(data: data, encoding: .utf8),
          let end = text.range(of: "\n..."), text[..<end.lowerBound].contains("---") else {
      throw DictionaryFailure(message: "文件不是 UTF-8 Rime 词库，缺少 YAML 头部。")
    }
    let api = rime_get_api_stdbool().pointee
    var config = RimeConfig()
    defer { _ = api.config_close(&config) }
    let header = String(text[..<end.lowerBound])
    guard api.config_load_string(&config, header), api.config_get_cstring(&config, "version") != nil, let namePointer = api.config_get_cstring(&config, "name") else {
      throw DictionaryFailure(message: "词库 YAML 头部无效，或缺少 name / version 字段。")
    }
    let name = String(cString: namePointer)
    if requireDependencies && api.config_list_size(&config, "import_tables") > 0 {
      throw DictionaryFailure(message: "请导入包含实际词条的独立词库；暂不支持带 import_tables 的词库入口文件。")
    }
    guard !name.isEmpty, name.range(of: "^[A-Za-z0-9_/-]+$", options: .regularExpression) != nil,
          !name.contains(".."), !name.hasPrefix("/") else {
      throw DictionaryFailure(message: "词库 name 格式不支持。")
    }
    return name
  }

  private func checkedURL(_ path: String) throws -> URL {
    guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
      throw DictionaryFailure(message: "无效的词库路径。")
    }
    let url = root.appendingPathComponent(path)
    guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
      throw DictionaryFailure(message: "词库路径指向用户目录之外。")
    }
    return url
  }

  /// Back up every affected file before replacing anything; roll back on a write error.
  private func transaction(_ changes: [String: Data], removing: [String] = []) throws {
    let paths = Array(Set(Array(changes.keys) + removing)).sorted()
    var previous: [String: Data] = [:]
    let backup = metadata.appendingPathComponent("backups/\(UUID().uuidString)")
    for path in paths {
      let url = try checkedURL(path)
      if files.fileExists(atPath: url.path) {
        previous[path] = try Data(contentsOf: url)
        let destination = backup.appendingPathComponent(path)
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try previous[path]!.write(to: destination, options: .atomic)
      }
    }
    var changed: [String] = []
    do {
      for path in paths {
        let url = try checkedURL(path)
        if let data = changes[path] {
          try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
          try writeFile(data, url)
        } else {
          try files.removeItem(at: url)
        }
        changed.append(path)
      }
    } catch {
      let failure = error
      var rollbackErrors: [String] = []
      for path in changed.reversed() {
        do {
          let url = try checkedURL(path)
          if let data = previous[path] { try writeFile(data, url) }
          else if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
        } catch { rollbackErrors.append("\(path): \(error.localizedDescription)") }
      }
      if !rollbackErrors.isEmpty {
        throw DictionaryFailure(message: "写入失败：\(failure.localizedDescription)。部分文件无法恢复：\(rollbackErrors.joined(separator: "; "))。备份：\(backup.path)")
      }
      throw failure
    }
  }

  /// Rime imports are not recursive; attach to the dictionary selected by the deployed schema.
  private func entryPoint() throws -> String {
    let schema = try checkedURL("build/rime_ice.schema.yaml")
    guard files.fileExists(atPath: schema.path) else { return "rime_ice.dict.yaml" }
    let api = rime_get_api_stdbool().pointee
    var config = RimeConfig()
    defer { _ = api.config_close(&config) }
    let yaml = try String(contentsOf: schema, encoding: .utf8)
    guard api.config_load_string(&config, yaml), let pointer = api.config_get_cstring(&config, "translator/dictionary") else {
      throw DictionaryFailure(message: "无法识别当前雾凇方案的词库入口，请先重新部署。")
    }
    let name = String(cString: pointer)
    guard name.range(of: "^[A-Za-z0-9_/-]+$", options: .regularExpression) != nil else {
      throw DictionaryFailure(message: "当前词库入口名称不支持。")
    }
    let path = name + ".dict.yaml"
    _ = try checkedURL(path)
    return path
  }

  func importDictionary(from url: URL) throws {
    let data = try Data(contentsOf: url)
    let name = try dictionaryName(data, requireDependencies: true)
    guard !name.contains("/") else { throw DictionaryFailure(message: "导入词库的 name 不能包含目录。") }
    let path = name + ".dict.yaml"
    guard !files.fileExists(atPath: root.appendingPathComponent(path).path) else {
      throw DictionaryFailure(message: "同名词库已存在，未覆盖。")
    }
    let entry = try entryPoint()
    var main = try String(contentsOf: checkedURL(entry), encoding: .utf8)
    guard let end = main.range(of: "\n..."), main[..<end.lowerBound].contains("\nimport_tables:\n") else {
      throw DictionaryFailure(message: "未找到雾凇拼音 import_tables，无法自动挂载。")
    }
    // Insert immediately after import_tables so unrelated YAML fields cannot capture the entry.
    main = main.replacingOccurrences(of: "\nimport_tables:\n", with: "\nimport_tables:\n  - '\(name)'\n")
    let managed = try imports() + [path]
    try transaction([path: data, entry: Data(main.utf8),
                     ".squirrel-dictionaries/imports.json": try JSONEncoder().encode(managed)])
  }

  func removeDictionary(path: String) throws {
    let managed = try imports()
    guard managed.contains(path) else { throw DictionaryFailure(message: "仅可移除此窗口导入的词库。") }
    let name = String(path.dropLast(".dict.yaml".count))
    let targetEntry = try entryPoint()
    for entry in try entries() where entry.path != path && entry.path != targetEntry {
      let data = try Data(contentsOf: checkedURL(entry.path))
      guard let text = String(data: data, encoding: .utf8), let end = text.range(of: "\n...") else { continue }
      let api = rime_get_api_stdbool().pointee
      var config = RimeConfig()
      defer { _ = api.config_close(&config) }
      guard api.config_load_string(&config, String(text[..<end.lowerBound])) else {
        throw DictionaryFailure(message: "无法检查词库引用：\(entry.path)")
      }
      for index in 0..<api.config_list_size(&config, "import_tables") {
        if let dependency = api.config_get_cstring(&config, "import_tables/@\(index)"), String(cString: dependency) == name {
          throw DictionaryFailure(message: "\(entry.path) 仍在引用此词库，请先移除该引用。")
        }
      }
    }
    let main = try String(contentsOf: checkedURL(targetEntry), encoding: .utf8)
    guard main.contains("\n  - '\(name)'\n") else {
      throw DictionaryFailure(message: "词库引用已被手动修改，请在配置目录中处理。")
    }
    try transaction([targetEntry: Data(main.replacingOccurrences(of: "\n  - '\(name)'\n", with: "\n").utf8),
                     ".squirrel-dictionaries/imports.json": try JSONEncoder().encode(managed.filter { $0 != path })], removing: [path])
  }

  func installUpdates(_ updates: [String: Data]) throws {
    for (path, data) in updates {
      guard Self.updatePaths.contains(path) else { throw DictionaryFailure(message: "更新包含未授权的词库路径。") }
      _ = try checkedURL(path)
      let old = try Data(contentsOf: root.appendingPathComponent(path))
      guard try dictionaryName(old) == dictionaryName(data) else {
        throw DictionaryFailure(message: "更新词库名称与本地文件不匹配：\(path)")
      }
    }
    try transaction(updates)
  }

  func downloadUpdates(progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> [String: Data] {
    var updates: [String: Data] = [:]
    let paths = Self.updatePaths.filter { files.fileExists(atPath: root.appendingPathComponent($0).path) }
    guard !paths.isEmpty else { throw DictionaryFailure(message: "未找到已安装的雾凇拼音词库。") }
    await progress(0, paths.count)
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 300
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    // Pin all files to a single revision, even if upstream changes during the download.
    var request = URLRequest(url: URL(string: "https://api.github.com/repos/iDvel/rime-ice/commits/main")!)
    request.setValue("Squirrel-Dictionary-Updater", forHTTPHeaderField: "User-Agent")
    let (revisionData, revisionResponse) = try await session.data(for: request)
    guard (revisionResponse as? HTTPURLResponse)?.statusCode == 200 else {
      throw DictionaryFailure(message: "无法查询雾凇词库版本，请稍后重试。")
    }
    struct Revision: Decodable { let sha: String }
    let revision = try JSONDecoder().decode(Revision.self, from: revisionData).sha
    guard revision.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
      throw DictionaryFailure(message: "上游返回了无效版本。")
    }
    for path in paths {
      let url = URL(string: "https://raw.githubusercontent.com/iDvel/rime-ice/\(revision)/\(path)")!
      let (data, response) = try await session.data(from: url)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw DictionaryFailure(message: "下载失败：\(path)")
      }
      updates[path] = data
      await progress(updates.count, paths.count)
    }
    return updates
  }
}
