import AppKit
import Combine

class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private var activeDisplayTimer: Timer?
    private var hideActiveDisplayTimer: Timer?
    private var showActiveElapsed = false

    private static let currentTaskDisplayTag = 1
    private static let breakStatusTag        = 2
    private static let confirmBreakTag       = 3

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
        subscribeToAppState()
        startActiveElapsedCycle()
    }

    // MARK: - Setup

    private func configure() {
        guard let button = statusItem.button else { return }
        buildMenu()
        menu.delegate = self
        button.target = self
        button.action = #selector(statusBarButtonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateMenuBarDisplay()
    }

    private func subscribeToAppState() {
        AppState.shared.$currentTask
            .combineLatest(AppState.shared.$showMenuBarText)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateMenuBarDisplay() }
            .store(in: &cancellables)

        AppState.shared.$currentTaskColorMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarDisplay() }
            .store(in: &cancellables)

        BreakTimer.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarDisplay() }
            .store(in: &cancellables)

        BreakDisplayTimer.shared.$isPeriodicBreakVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarDisplay() }
            .store(in: &cancellables)
    }

    // MARK: - Menu bar display

    private func updateMenuBarDisplay() {
        let mode = StatusBarPresenter.mode(
            appState: AppState.shared,
            breakState: BreakTimer.shared.state,
            isPeriodicBreakVisible: BreakDisplayTimer.shared.isPeriodicBreakVisible
            ,
            showActiveElapsed: showActiveElapsed,
            activeElapsed: BreakTimer.shared.activeElapsed
        )
        let title = StatusBarPresenter.menuBarTitle(for: mode)
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        applyMenuBarTitle(title, mode: mode)
        statusItem.button?.toolTip = task.isEmpty ? "Keystone2" : task
    }

    private func applyMenuBarTitle(_ title: String, mode: StatusBarMode) {
        guard let button = statusItem.button else { return }
        let displayTitle = title.isEmpty ? "" : " \(title)"
        guard case .currentTask = mode,
              let color = currentTaskTextColor(),
              !displayTitle.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = displayTitle
            return
        }
        button.title = ""
        button.attributedTitle = NSAttributedString(
            string: displayTitle,
            attributes: [.foregroundColor: color]
        )
    }

    private func currentTaskTextColor() -> NSColor? {
        switch AppState.shared.currentTaskColorMode {
        case .system: return nil
        case .black:  return .black
        case .red:    return .systemRed
        }
    }

    private func startActiveElapsedCycle() {
        activeDisplayTimer?.invalidate()
        activeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard BreakTimer.shared.state == .focusing else { return }
            showActiveElapsed = true
            updateMenuBarDisplay()
            hideActiveDisplayTimer?.invalidate()
            hideActiveDisplayTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.showActiveElapsed = false
                self?.updateMenuBarDisplay()
            }
        }
    }

    // MARK: - Menu structure

    private func buildMenu() {
        menu.removeAllItems()

        // 设置
        let settings = NSMenuItem(title: "设置\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        // 当前事项：显示当前值（disabled）+ 修改入口
        let taskDisplay = NSMenuItem(title: currentTaskDisplayTitle(), action: nil, keyEquivalent: "")
        taskDisplay.isEnabled = false
        taskDisplay.tag = Self.currentTaskDisplayTag
        menu.addItem(taskDisplay)

        let editTask = NSMenuItem(title: "修改当前事项\u{2026}", action: #selector(editCurrentTask), keyEquivalent: "")
        editTask.target = self
        menu.addItem(editTask)

        menu.addItem(.separator())

        // 休息提醒区域
        let breakStatus = NSMenuItem(title: breakStatusTitle(), action: nil, keyEquivalent: "")
        breakStatus.isEnabled = false
        breakStatus.tag = Self.breakStatusTag
        menu.addItem(breakStatus)

        let confirmBreak = NSMenuItem(title: breakActionTitle(), action: #selector(handleBreakAction), keyEquivalent: "")
        confirmBreak.target = self
        confirmBreak.tag = Self.confirmBreakTag
        confirmBreak.isEnabled = (BreakTimer.shared.state == .focusing || BreakTimer.shared.state == .breakDue)
        menu.addItem(confirmBreak)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "关于 Keystone2", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let help = NSMenuItem(title: "帮助", action: #selector(showHelp), keyEquivalent: "?")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())
        let restart = NSMenuItem(title: "重启 Keystone2", action: #selector(restartApp), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        menu.addItem(NSMenuItem(title: "退出 Keystone2", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func currentTaskDisplayTitle() -> String {
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        return task.isEmpty ? "当前事项：（未设置）" : "当前事项：\(StatusBarPresenter.truncate(task))"
    }

    private func breakStatusTitle() -> String {
        switch BreakTimer.shared.state {
        case .disabled:  return "休息提醒：已关闭"
        case .focusing:  return "休息提醒：专注中"
        case .breakDue:  return "休息提醒：休息到期！"
        }
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: statusItem.button?.bounds.height ?? 0), in: statusItem.button!)
            return
        }
        // 根据当前显示状态分发左键行为
        let mode = currentDisplayMode()
        switch mode {
        case .breakDue:
            BreakTimer.shared.confirmBreak()
        case .periodicBreak:
            BreakTimer.shared.forceBreak()
        default:
            editCurrentTask()
        }
    }

    private func currentDisplayMode() -> StatusBarMode {
        StatusBarPresenter.mode(
            appState: AppState.shared,
            breakState: BreakTimer.shared.state,
            isPeriodicBreakVisible: BreakDisplayTimer.shared.isPeriodicBreakVisible,
            showActiveElapsed: showActiveElapsed,
            activeElapsed: BreakTimer.shared.activeElapsed
        )
    }

    private var editTaskAlertShowing = false

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func editCurrentTask() {
        guard !editTaskAlertShowing else { return }
        editTaskAlertShowing = true

        let alert = NSAlert()
        alert.messageText = "当前最重要的一件事"
        alert.informativeText = "留空或点击「清空」可移除当前事项。"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        tf.stringValue = AppState.shared.currentTask
        tf.placeholderString = "输入当前最重要的事项…"
        alert.accessoryView = tf
        alert.window.initialFirstResponder = tf

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            AppState.shared.currentTask = tf.stringValue.trimmingCharacters(in: .whitespaces)
        case .alertSecondButtonReturn:
            AppState.shared.currentTask = ""
        default:
            break
        }

        editTaskAlertShowing = false
    }

    private func breakActionTitle() -> String {
        switch BreakTimer.shared.state {
        case .focusing: return "点击去休息"
        case .breakDue: return "已休息，继续专注"
        default:        return ""
        }
    }

    @objc private func handleBreakAction() {
        switch BreakTimer.shared.state {
        case .focusing: BreakTimer.shared.forceBreak()
        case .breakDue: BreakTimer.shared.confirmBreak()
        default: break
        }
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 Beke. All rights reserved."

        let alert = NSAlert()
        alert.messageText = "Keystone2"
        alert.informativeText = """
        版本 \(version)（\(build)）

        一款个人使用的 macOS 菜单栏工具，聚合截图标注、OCR 识别、屏幕标注、当前事项与休息提醒。

        \(copyright)
        基于 MIT License 开源。
        """
        alert.alertStyle = .informational
        let appIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        appIcon.size = NSSize(width: 64, height: 64)
        alert.icon = appIcon
        alert.addButton(withTitle: "确定")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        NSApp.terminate(nil)
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Keystone2 帮助"
        alert.informativeText = """
        F1: 截图、标注、复制、保存或钉图
        F2: OCR 识别屏幕文字
        F3: 屏幕标注和鼠标高亮

        菜单栏可设置当前事项、休息提醒、快捷键、开机自启动和当前事项颜色。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: Self.currentTaskDisplayTag)?.title = currentTaskDisplayTitle()
        menu.item(withTag: Self.breakStatusTag)?.title = breakStatusTitle()
        menu.item(withTag: Self.confirmBreakTag)?.title = breakActionTitle()
        menu.item(withTag: Self.confirmBreakTag)?.isEnabled = (BreakTimer.shared.state == .focusing || BreakTimer.shared.state == .breakDue)
    }
}
