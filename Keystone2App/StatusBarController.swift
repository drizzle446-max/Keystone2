import AppKit
import Carbon
import Combine

class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()
    private var cycleTimer: Timer?
    private var showActiveElapsed = false
    private var showBreakHint = false
    private var cyclePhase = 0  // 0=task  1=elapsed  2=hint
    private var currentMode: StatusBarMode = .iconOnly
    private let noTaskBreakPromptDisplaySeconds: TimeInterval = 5
    private let noTaskFocusRefreshSeconds: TimeInterval = 5

    private static let currentTaskDisplayTag = 1
    private static let breakStatusTag        = 2
    private static let confirmBreakTag       = 3

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
        subscribeToAppState()
        startDisplayCycle()
    }

    // MARK: - Setup

    private func configure() {
        guard let button = statusItem.button else { return }
        menu.showsStateColumn = false
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
            .sink { [weak self] _, _ in
                self?.restartCycleIfNeeded()
                self?.updateMenuBarDisplay()
            }
            .store(in: &cancellables)

        AppState.shared.$currentTaskColorMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarDisplay() }
            .store(in: &cancellables)

        BreakTimer.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                self?.updateMenuBarDisplay()
                if newState == .focusing || newState == .breakPrompt {
                    self?.startDisplayCycle()
                } else {
                    self?.cycleTimer?.invalidate()
                    self?.showActiveElapsed = false
                    self?.showBreakHint = false
                }
            }
            .store(in: &cancellables)

        BreakDisplayTimer.shared.$isPeriodicBreakVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateMenuBarDisplay() }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            AppState.shared.$taskDisplaySeconds,
            AppState.shared.$elapsedDisplaySeconds,
            AppState.shared.$hintDisplaySeconds
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _ in self?.restartCycleIfNeeded() }
        .store(in: &cancellables)
    }

    // MARK: - Menu bar display

    private func updateMenuBarDisplay() {
        let breakState = BreakTimer.shared.state
        let elapsed = breakState == .breakPrompt
            ? BreakTimer.shared.focusedDuration
            : BreakTimer.shared.activeElapsed
        let mode = StatusBarPresenter.mode(
            appState: AppState.shared,
            breakState: breakState,
            isPeriodicBreakVisible: BreakDisplayTimer.shared.isPeriodicBreakVisible,
            showActiveElapsed: showActiveElapsed,
            showBreakHint: showBreakHint,
            activeElapsed: elapsed
        )
        let title = StatusBarPresenter.menuBarTitle(for: mode)
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        currentMode = mode
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
        case .red:    return .systemRed
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .black:  return .black
        }
    }

    private func startDisplayCycle() {
        cycleTimer?.invalidate()
        cyclePhase = initialCyclePhase()
        applyCyclePhase()
        updateMenuBarDisplay()
        scheduleNextCycleStep()
    }

    private func restartCycleIfNeeded() {
        let state = BreakTimer.shared.state
        guard state == .focusing || state == .breakPrompt else { return }
        startDisplayCycle()
    }

    private func scheduleNextCycleStep() {
        cycleTimer?.invalidate()
        let state = BreakTimer.shared.state
        guard state == .focusing || state == .breakPrompt else { return }

        let duration = currentCycleDuration(state: state)
        cycleTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            let currentState = BreakTimer.shared.state
            guard currentState == .focusing || currentState == .breakPrompt else { return }

            cyclePhase = nextCyclePhase(state: currentState)
            applyCyclePhase()
            updateMenuBarDisplay()
            scheduleNextCycleStep()
        }
    }

    private func initialCyclePhase() -> Int {
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        if task.isEmpty { return 1 }
        return 0
    }

    private func currentCycleDuration(state: BreakTimerState) -> TimeInterval {
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        if state == .focusing, task.isEmpty {
            return noTaskFocusRefreshSeconds
        }
        if state == .breakPrompt, task.isEmpty {
            return noTaskBreakPromptDisplaySeconds
        }
        switch cyclePhase {
        case 0:  return TimeInterval(AppState.shared.taskDisplaySeconds)
        case 1:  return TimeInterval(AppState.shared.elapsedDisplaySeconds)
        default: return TimeInterval(AppState.shared.hintDisplaySeconds)
        }
    }

    private func nextCyclePhase(state: BreakTimerState) -> Int {
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        if state == .focusing {
            return task.isEmpty ? 1 : (cyclePhase == 0 ? 1 : 0)
        }
        if task.isEmpty {
            return cyclePhase == 1 ? 2 : 1
        }
        switch cyclePhase {
        case 0:  return 1
        case 1:  return 2
        default: return 0
        }
    }

    private func applyCyclePhase() {
        showActiveElapsed = cyclePhase == 1
        showBreakHint = cyclePhase == 2
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
        confirmBreak.isEnabled = BreakTimer.shared.state != .disabled
        menu.addItem(confirmBreak)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "关于", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let help = NSMenuItem(title: "帮助", action: #selector(showHelp), keyEquivalent: "?")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())
        let restart = NSMenuItem(title: "重启", action: #selector(restartApp), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func currentTaskDisplayTitle() -> String {
        let task = AppState.shared.currentTask.trimmingCharacters(in: .whitespaces)
        return task.isEmpty ? "事项：（未设置）" : "事项：\(StatusBarPresenter.truncate(task))"
    }

    private func breakStatusTitle() -> String {
        switch BreakTimer.shared.state {
        case .disabled:     return "状态：已关闭"
        case .focusing:     return "状态：\(StatusBarPresenter.formatElapsed(BreakTimer.shared.activeElapsed))"
        case .breakPrompt:  return "状态：该休息了"
        case .resting:      return "状态：休息中"
        }
    }

    // MARK: - Actions

    @objc private func statusBarButtonClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: statusItem.button?.bounds.height ?? 0), in: statusItem.button!)
            return
        }
        switch BreakTimer.shared.state {
        case .breakPrompt:
            handleBreakPromptLeftClick()
        case .resting:
            BreakTimer.shared.confirmRest()
        default:
            editCurrentTask()
        }
    }

    private func handleBreakPromptLeftClick() {
        switch currentMode {
        case .currentTask:
            editCurrentTask()
        case .activeElapsed, .breakHint, .periodicBreak:
            BreakTimer.shared.enterRest()
        case .iconOnly, .resting:
            BreakTimer.shared.enterRest()
        }
    }

    private var editTaskAlertShowing = false
    private var taskEditDelegate: TaskEditPanelDelegate?
    private var helpPanel: NSPanel?
    private var aboutPanel: NSPanel?
    private var menuEventTap: CFMachPort?
    private var menuEventTapSource: CFRunLoopSource?

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func editCurrentTask() {
        guard !editTaskAlertShowing else { return }
        editTaskAlertShowing = true

        let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        tf.stringValue = AppState.shared.currentTask
        tf.placeholderString = "输入当前最重要的事项…"

        let confirmBtn = NSButton(title: "确定", target: nil, action: nil)
        confirmBtn.keyEquivalent = "\r"
        confirmBtn.bezelStyle = .rounded
        confirmBtn.isHighlighted = true

        let clearBtn = NSButton(title: "清空", target: nil, action: nil)
        clearBtn.bezelStyle = .rounded

        let cancelBtn = NSButton(title: "取消", target: nil, action: nil)
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.bezelStyle = .rounded

        let btnStack = NSStackView(views: [cancelBtn, clearBtn, confirmBtn])
        btnStack.spacing = 8
        btnStack.alignment = .centerY
        btnStack.distribution = .equalSpacing

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 72))
        content.addSubview(tf)
        content.addSubview(btnStack)

        tf.translatesAutoresizingMaskIntoConstraints = false
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tf.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            tf.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tf.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            btnStack.topAnchor.constraint(equalTo: tf.bottomAnchor, constant: 16),
            btnStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            content.bottomAnchor.constraint(equalTo: btnStack.bottomAnchor, constant: 12),
        ])

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 84),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = content
        panel.isFloatingPanel = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let delegate = TaskEditPanelDelegate(panel: panel,
            onConfirm: { [weak self] in
                AppState.shared.currentTask = tf.stringValue.trimmingCharacters(in: .whitespaces)
                self?.editTaskAlertShowing = false
                self?.taskEditDelegate = nil
            },
            onClear: { [weak self] in
                AppState.shared.currentTask = ""
                self?.editTaskAlertShowing = false
                self?.taskEditDelegate = nil
            },
            onCancel: { [weak self] in
                self?.editTaskAlertShowing = false
                self?.taskEditDelegate = nil
            }
        )
        taskEditDelegate = delegate

        confirmBtn.target = delegate
        confirmBtn.action = #selector(TaskEditPanelDelegate.confirm)
        clearBtn.target = delegate
        clearBtn.action = #selector(TaskEditPanelDelegate.clear)
        cancelBtn.target = delegate
        cancelBtn.action = #selector(TaskEditPanelDelegate.cancel)
        panel.delegate = delegate
    }

    private func breakActionTitle() -> String {
        switch BreakTimer.shared.state {
        case .focusing, .breakPrompt: return "休息一下"
        case .resting:                return "继续专注"
        case .disabled:               return ""
        }
    }

    @objc private func handleBreakAction() {
        switch BreakTimer.shared.state {
        case .focusing, .breakPrompt: BreakTimer.shared.enterRest()
        case .resting:                BreakTimer.shared.confirmRest()
        case .disabled:               break
        }
    }

    @objc private func showAbout() {
        if let p = aboutPanel {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),
        ])

        let versionStr = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let nameLbl    = aboutLabel("Keystone2", size: 20, weight: .semibold)
        let versionLbl = aboutLabel("版本 \(versionStr)", size: 13, color: .secondaryLabelColor)
        let descLbl    = aboutWrappingLabel(
            "一款 macOS 菜单栏工具，用于截图标注、OCR 识别、屏幕标注、当前事项与休息提醒。",
            maxWidth: 500
        )
        let licenseLbl = aboutLabel("基于 MIT License 开源。", size: 13, color: .secondaryLabelColor)

        let stack = NSStackView(views: [iconView, nameLbl, versionLbl, descLbl, licenseLbl])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(12, after: iconView)
        stack.setCustomSpacing(5,  after: nameLbl)
        stack.setCustomSpacing(14, after: versionLbl)
        stack.setCustomSpacing(12, after: descLbl)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 520),
        ])

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "关于 Keystone2"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.contentView = content
        installPanelTitle("关于 Keystone2", in: panel)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        aboutPanel = panel
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        NSApp.terminate(nil)
    }

    @objc private func showHelp() {
        if let p = helpPanel {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let shortcutsTitle = helpSectionLabel("Keystone2 快捷键")
        let rowViews = [
            helpShortcutRow(key: "F1", desc: "截图、标注、复制、保存或钉图"),
            helpShortcutRow(key: "F2", desc: "OCR 识别屏幕文字"),
            helpShortcutRow(key: "F3", desc: "屏幕标注与鼠标高亮"),
        ]

        let sep = NSBox()
        sep.boxType = .separator

        let menuTitle = helpSectionLabel("菜单栏设置")

        let menuDesc = NSTextField(wrappingLabelWithString:
            "可在菜单栏中设置显示事项、休息提醒、快捷键、开机自启动和文字颜色。"
        )
        menuDesc.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        menuDesc.textColor = .secondaryLabelColor
        menuDesc.preferredMaxLayoutWidth = 460

        let linkBtn = NSButton(title: "", target: self, action: #selector(openGitHub))
        linkBtn.isBordered = false
        linkBtn.bezelStyle = .inline
        linkBtn.attributedTitle = NSAttributedString(
            string: "GitHub Repository",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            ]
        )
        linkBtn.alignment = .left
        linkBtn.setContentHuggingPriority(.required, for: .horizontal)

        let mainStack = NSStackView(
            views: [shortcutsTitle] + rowViews + [sep, menuTitle, menuDesc, linkBtn]
        )
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        // separator and wrapping description should span the full stack width
        sep.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        menuDesc.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        mainStack.setCustomSpacing(10, after: shortcutsTitle)
        for (i, row) in rowViews.enumerated() {
            mainStack.setCustomSpacing(i < rowViews.count - 1 ? 7 : 18, after: row)
        }
        mainStack.setCustomSpacing(18, after: sep)
        mainStack.setCustomSpacing(8,  after: menuTitle)
        mainStack.setCustomSpacing(36, after: menuDesc)

        let content = NSView()
        content.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 52),
            mainStack.widthAnchor.constraint(equalToConstant: 460),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -30),
        ])

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "帮助"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.contentView = content
        installPanelTitle("帮助", in: panel)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        helpPanel = panel
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/drizzle446-max/Keystone2")!)
    }

    // MARK: - About & Help UI helpers

    private func installPanelTitle(_ title: String, in panel: NSPanel) {
        guard let titlebarView = panel.standardWindowButton(.closeButton)?.superview else { return }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlebarView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: titlebarView.centerYAnchor),
        ])
    }

    private func aboutLabel(_ text: String, size: CGFloat,
                            weight: NSFont.Weight = .regular,
                            color: NSColor = .labelColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.alignment = .center
        return f
    }

    private func aboutWrappingLabel(_ text: String, maxWidth: CGFloat) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        f.textColor = .secondaryLabelColor
        f.alignment = .center
        f.preferredMaxLayoutWidth = maxWidth
        return f
    }

    private func helpSectionLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        f.textColor = .secondaryLabelColor
        return f
    }

    private func helpShortcutRow(key: String, desc: String) -> NSStackView {
        let pill = KeyPillView(key: key)

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        descLabel.textColor = .labelColor
        descLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [pill, descLabel])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.forEach { $0.image = nil }
        menu.item(withTag: Self.currentTaskDisplayTag)?.title = currentTaskDisplayTitle()
        menu.item(withTag: Self.breakStatusTag)?.title = breakStatusTitle()
        menu.item(withTag: Self.confirmBreakTag)?.title = breakActionTitle()
        menu.item(withTag: Self.confirmBreakTag)?.isEnabled = BreakTimer.shared.state != .disabled

        // Carbon hotkeys don't fire during NSMenu tracking (private modal runloop).
        // CGEvent tap runs below the runloop and intercepts keyDown regardless of mode.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: menuHotkeyTapCallback,
            userInfo: selfPtr
        ) {
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)!
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            menuEventTap = tap
            menuEventTapSource = src
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if let tap = menuEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = menuEventTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            menuEventTap = nil
            menuEventTapSource = nil
        }
    }

    fileprivate func handleMenuKeyEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        let kc = UInt32(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        let flags = cgEvent.flags
        var mods: UInt32 = 0
        if flags.contains(.maskCommand)   { mods |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { mods |= UInt32(optionKey) }
        if flags.contains(.maskControl)   { mods |= UInt32(controlKey) }
        if flags.contains(.maskShift)     { mods |= UInt32(shiftKey) }
        let pressed = HotkeyBinding(keyCode: kc, carbonModifiers: mods)
        for action in HotkeyAction.allCases {
            if HotkeyStore.shared.binding(for: action) == pressed {
                DispatchQueue.main.async { [weak self] in
                    self?.menu.cancelTracking()
                    HotkeyManager.shared.didReceiveHotkey(id: action.rawValue)
                }
                return nil
            }
        }
        return Unmanaged.passUnretained(cgEvent)
    }
}

// MARK: - Task edit panel delegate

private class TaskEditPanelDelegate: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let onConfirm: () -> Void
    private let onClear: () -> Void
    private let onCancel: () -> Void
    private var dismissed = false

    init(panel: NSPanel,
         onConfirm: @escaping () -> Void,
         onClear: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.panel = panel
        self.onConfirm = onConfirm
        self.onClear = onClear
        self.onCancel = onCancel
        super.init()
    }

    @objc func confirm() {
        guard !dismissed else { return }
        dismissed = true
        onConfirm()
        panel.close()
    }

    @objc func clear() {
        guard !dismissed else { return }
        dismissed = true
        onClear()
        panel.close()
    }

    @objc func cancel() {
        guard !dismissed else { return }
        dismissed = true
        onCancel()
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !dismissed else { return }
        dismissed = true
        onCancel()
    }
}

// MARK: - CGEvent tap callback for hotkeys during NSMenu tracking

private func menuHotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown, let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<StatusBarController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handleMenuKeyEvent(event)
}

// MARK: - Key pill view (dark-mode aware)

private final class KeyPillView: NSView {
    init(key: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: key)
        label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 44),
            heightAnchor.constraint(equalToConstant: 25),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
}
