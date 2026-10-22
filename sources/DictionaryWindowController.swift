import AppKit
import UniformTypeIdentifiers

final class DictionaryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
  private let store: DictionaryStore
  private let deploy: () -> Void
  private var state = DictionaryUpdateState()
  private var entries: [DictionaryEntry] = []
  private var timer: Timer?
  private var busy = false
  private let storageQueue = DispatchQueue(label: "im.rime.squirrel.dictionaries", qos: .utility)
  private let table = NSTableView()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let automatic = NSButton(checkboxWithTitle: "每周自动更新雾凇拼音词库", target: nil, action: nil)
  private let update = NSButton(title: "立即更新", target: nil, action: nil)
  private let importButton = NSButton(title: "导入词库…", target: nil, action: nil)
  private let removeButton = NSButton(title: "移除导入词库", target: nil, action: nil)

  init(root: URL, deploy: @escaping () -> Void) {
    store = DictionaryStore(root: root)
    self.deploy = deploy
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "词库管理"
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 580, height: 420)
    super.init(window: window)
    configureWindow()
    do { state = try store.loadState() } catch { state.message = "读取更新设置失败：\(error.localizedDescription)" }
    refresh()
  }

  required init?(coder: NSCoder) { nil }

  func startScheduler() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.checkSchedule() }
    checkSchedule()
  }

  deinit { timer?.invalidate() }

  func present() {
    refresh()
    window?.center()
    showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  private func configureWindow() {
    guard let content = window?.contentView else { return }
    let title = NSTextField(labelWithString: "雾凇拼音词库")
    title.font = .boldSystemFont(ofSize: 20)
    let description = NSTextField(wrappingLabelWithString: "查看本地词库，导入 UTF-8 .dict.yaml 文件。导入词库会自动挂载到当前雾凇词库入口；仅可移除此窗口导入的词库。")
    let column = NSTableColumn(identifier: .init("dictionary"))
    column.title = "词库文件"
    column.width = 450
    table.addTableColumn(column)
    let source = NSTableColumn(identifier: .init("source"))
    source.title = "管理方式"
    source.width = 140
    table.addTableColumn(source)
    table.dataSource = self
    table.delegate = self
    table.usesAlternatingRowBackgroundColors = true
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    automatic.target = self
    automatic.action = #selector(toggleAutomatic)
    update.target = self
    update.action = #selector(updateNow)
    importButton.target = self
    importButton.action = #selector(importDictionary)
    removeButton.target = self
    removeButton.action = #selector(removeDictionary)
    let folder = NSButton(title: "打开词库目录", target: self, action: #selector(openFolder))
    let buttons = NSStackView(views: [importButton, removeButton, folder])
    buttons.spacing = 8
    let schedule = NSStackView(views: [automatic, update])
    schedule.spacing = 20
    let note = NSTextField(wrappingLabelWithString: "更新来源：iDvel/rime-ice。更新已安装的中英文分词库，保留个人词库与学习记录。每次修改前保存备份，完成后重新部署。")
    note.font = .systemFont(ofSize: 11)
    note.textColor = .secondaryLabelColor
    let stack = NSStackView(views: [title, description, scroll, buttons, schedule, status, note])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
      description.widthAnchor.constraint(equalTo: stack.widthAnchor),
      status.widthAnchor.constraint(equalTo: stack.widthAnchor),
      note.widthAnchor.constraint(equalTo: stack.widthAnchor)
    ])
  }

  func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let entry = entries[row]
    let value = tableColumn?.identifier.rawValue == "dictionary" ? entry.path
      : entry.removable ? "手动导入" : DictionaryStore.updatePaths.contains(entry.path) ? "雾凇更新" : "本地词库"
    return NSTextField(labelWithString: value)
  }

  func tableViewSelectionDidChange(_ notification: Notification) { updateControls() }

  private func refresh() {
    if !busy {
      do { entries = try store.entries() } catch { state.message = error.localizedDescription }
      table.reloadData()
    }
    automatic.state = state.enabled ? .on : .off
    var message = state.message
    if let last = state.lastSuccess {
      message += "\n上次更新：\(last.formatted(date: .abbreviated, time: .shortened))"
      if state.enabled {
        message += "；下次：\(last.addingTimeInterval(7 * 86400).formatted(date: .abbreviated, time: .shortened))"
      }
    }
    status.stringValue = message
    updateControls()
  }

  private func updateControls() {
    update.isEnabled = !busy
    importButton.isEnabled = !busy
    automatic.isEnabled = !busy
    let row = table.selectedRow
    removeButton.isEnabled = !busy && row >= 0 && row < entries.count && entries[row].removable
  }

  private func showError(_ error: Error) {
    let alert = NSAlert(error: error)
    if let window = window, window.isVisible { alert.beginSheetModal(for: window) }
    state.message = error.localizedDescription
    refresh()
  }

  @objc private func openFolder() { NSWorkspace.shared.open(store.root) }

  @objc private func toggleAutomatic() {
    state.enabled = automatic.state == .on
    do { try store.saveState(state) } catch { state.enabled.toggle(); showError(error); return }
    refresh()
    checkSchedule()
  }

  private func checkSchedule() {
    if state.isDue(at: Date()) { updateNow() }
  }

  @objc private func updateNow() {
    guard !busy else { return }
    busy = true
    state.lastAttempt = Date()
    state.message = "正在下载雾凇拼音词库…"
    do { try store.saveState(state) } catch { busy = false; showError(error); return }
    refresh()
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      do {
        let updates = try await self.store.downloadUpdates()
        try await self.performStorage { try self.store.installUpdates(updates) }
        self.state.lastSuccess = Date()
        self.state.message = "已更新 \(updates.count) 个词库，已请求重新部署。"
        self.deploy()
        do { try self.store.saveState(self.state) } catch {
          self.state.message += " 更新设置保存失败：\(error.localizedDescription)"
        }
      } catch {
        self.state.message = "更新失败：\(error.localizedDescription)；自动更新将在 6 小时后重试。"
        do { try self.store.saveState(self.state) } catch { self.state.message += " 设置保存失败：\(error.localizedDescription)" }
      }
      self.busy = false
      self.refresh()
    }
  }

  private func performStorage(_ work: @escaping () throws -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      storageQueue.async {
        do { try work(); continuation.resume() }
        catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func mutate(message: String, work: @escaping () throws -> Void) {
    busy = true
    state.message = "正在保存词库…"
    refresh()
    Task { @MainActor in
      do {
        try await self.performStorage(work)
        self.state.message = message
        self.deploy()
      } catch { self.showError(error) }
      self.busy = false
      self.refresh()
    }
  }

  @objc private func importDictionary() {
    guard !busy, let window = window else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .data]
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let self = self, let url = panel.url else { return }
      guard !self.busy else { self.showError(DictionaryFailure(message: "正在更新词库，请稍后重试导入。")); return }
      self.mutate(message: "词库已导入并挂载，已请求重新部署。") { try self.store.importDictionary(from: url) }
    }
  }

  @objc private func removeDictionary() {
    let row = table.selectedRow
    guard !busy, row >= 0, row < entries.count, entries[row].removable, let window = window else { return }
    let path = entries[row].path
    let alert = NSAlert()
    alert.messageText = "移除 \(path)？"
    alert.informativeText = "将移除词库文件和雾凇拼音中的引用。修改前会保存备份，个人学习记录保留。"
    alert.addButton(withTitle: "移除")
    alert.addButton(withTitle: "取消")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn, let self = self else { return }
      guard !self.busy else { self.showError(DictionaryFailure(message: "正在更新词库，请稍后重试移除。")); return }
      self.mutate(message: "词库已移除，已请求重新部署。") { try self.store.removeDictionary(path: path) }
    }
  }
}
