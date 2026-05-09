import AppKit
import SwiftUI
import Carbon

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabControl(selection: $selectedTab)
                .frame(width: 240, height: 28)
            .padding(.top, 18)
            .padding(.bottom, 18)

            Group {
                switch selectedTab {
                case .general:
                    GeneralTab()
                case .hotkeys:
                    HotkeysTab()
                case .permissions:
                    PermissionsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 760, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case hotkeys
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .hotkeys: return "快捷键"
        case .permissions: return "权限"
        }
    }
}

private struct SettingsTabControl: NSViewRepresentable {
    @Binding var selection: SettingsTab

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: SettingsTab.allCases.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        control.segmentStyle = .rounded
        control.controlSize = .regular
        control.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        control.selectedSegment = SettingsTab.allCases.firstIndex(of: selection) ?? 0
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        nsView.selectedSegment = SettingsTab.allCases.firstIndex(of: selection) ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        @Binding var selection: SettingsTab

        init(selection: Binding<SettingsTab>) {
            _selection = selection
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard SettingsTab.allCases.indices.contains(index) else { return }
            selection = SettingsTab.allCases[index]
        }
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var scrollManager = ScrollManager.shared
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared

    var body: some View {
        SettingsContentContainer(width: SettingsMetrics.generalContentWidth) {
            VStack(alignment: .leading, spacing: 13) {
                SettingsSection(title: "菜单栏显示") {
                    SettingsTextRow(label: "显示事项") {
                        TextField("", text: $state.currentTask)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .frame(width: 320)
                    }

                    SettingsDivider()

                    SettingsTextRow(label: "文字颜色") {
                        Picker("", selection: $state.currentTaskColorMode) {
                            ForEach(AppState.CurrentTaskColorMode.allCases) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 240)
                    }

                    SettingsDivider()

                    SettingsSwitchRow(label: "显示文字", isOn: $state.showMenuBarText)
                }

                SettingsSection(title: "休息提醒") {
                    SettingsSwitchRow(label: "启用休息提醒", isOn: $state.breakEnabled)

                    SettingsDivider()

                    NumericStepperRow(
                        label: "久坐提醒间隔",
                        suffix: "分钟",
                        value: $state.focusMinutes,
                        range: 10...120,
                        step: 5
                    )
                    .disabled(!state.breakEnabled)

                    SettingsDivider()

                    SettingsTextRow(label: "休息提示词") {
                        TextField("", text: $state.breakHintText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .frame(width: 320)
                            .disabled(!state.breakEnabled)
                    }
                }

                SettingsSection(title: "轮显设置") {
                    NumericStepperRow(label: "显示事项时长", suffix: "秒", value: $state.taskDisplaySeconds, range: 3...30, step: 1)
                        .disabled(!state.breakEnabled)

                    SettingsDivider()

                    NumericStepperRow(label: "专注时长显示", suffix: "秒", value: $state.elapsedDisplaySeconds, range: 1...10, step: 1)
                        .disabled(!state.breakEnabled)

                    SettingsDivider()

                    NumericStepperRow(label: "休息提示时长", suffix: "秒", value: $state.hintDisplaySeconds, range: 1...10, step: 1)
                        .disabled(!state.breakEnabled)

                    SettingsDivider()

                    SettingsSwitchRow(label: "鼠标滚轮翻转", isOn: $state.scrollEnabled)

                    SettingsDivider()

                    SettingsSwitchRow(label: "开机自启动", isOn: Binding(
                        get: { launchManager.isEnabled },
                        set: { launchManager.setEnabled($0) }
                    ))
                }

                if state.scrollEnabled && !scrollManager.isActive {
                    Text("未生效，请在「系统设置 > 隐私与安全性 > 辅助功能」中授予权限。")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }

                if let err = launchManager.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            launchManager.refresh()
            PermissionsManager.shared.checkPermissions()
            if state.scrollEnabled && !scrollManager.isActive {
                ScrollManager.shared.start()
            }
        }
    }
}

private struct SettingsContentContainer<Content: View>: View {
    let width: CGFloat
    @ViewBuilder var content: Content

    init(width: CGFloat = SettingsMetrics.generalContentWidth, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            content
                .frame(width: width, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor))
            .opacity(0.45)
    }
}

private enum SettingsMetrics {
    static let generalContentWidth: CGFloat = 600
    static let hotkeysContentWidth: CGFloat = 580
    static let permissionsContentWidth: CGFloat = 620
    static let labelWidth: CGFloat = 150
    static let controlWidth: CGFloat = 360
    static let rowHeight: CGFloat = 34
    static let columnSpacing: CGFloat = 12
}

private struct SettingsTextRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: SettingsMetrics.columnSpacing) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .labelColor))
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)
            content
                .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
        }
        .frame(height: SettingsMetrics.rowHeight)
    }
}

private struct SettingsSwitchRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.columnSpacing) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .labelColor))
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)
            MacSwitch(isOn: $isOn)
                .frame(width: 38, height: 22)
                .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
        }
        .frame(height: SettingsMetrics.rowHeight)
    }
}

private struct MacSwitch: NSViewRepresentable {
    @Binding var isOn: Bool

    func makeNSView(context: Context) -> NSSwitch {
        let view = NSSwitch()
        view.controlSize = .small
        view.scaleUnitSquare(to: NSSize(width: 0.75, height: 0.75))
        view.target = context.coordinator
        view.action = #selector(Coordinator.changed(_:))
        view.state = isOn ? .on : .off
        return view
    }

    func updateNSView(_ nsView: NSSwitch, context: Context) {
        nsView.state = isOn ? .on : .off
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    final class Coordinator: NSObject {
        @Binding var isOn: Bool

        init(isOn: Binding<Bool>) {
            _isOn = isOn
        }

        @objc func changed(_ sender: NSSwitch) {
            isOn = sender.state == .on
        }
    }
}

private struct NumericStepperRow: View {
    let label: String
    let suffix: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(alignment: .center, spacing: SettingsMetrics.columnSpacing) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .labelColor))
                .frame(width: SettingsMetrics.labelWidth, alignment: .leading)
            HStack(alignment: .center, spacing: 8) {
                TextField("", value: clampedValue, formatter: Self.integerFormatter)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(width: 68)
                Text(suffix)
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 34, alignment: .leading)
                Stepper("", value: clampedValue, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 20)
            }
            .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
        }
        .frame(height: SettingsMetrics.rowHeight)
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        return formatter
    }()
}

// MARK: - 快捷键录制状态机

private final class HotkeyRecorder: ObservableObject {
    @Published var recordingAction: HotkeyAction? = nil
    @Published var message: (text: String, isError: Bool)? = nil

    private var localMonitor: Any?
    private var globalMonitor: Any?

    func startRecording(_ action: HotkeyAction) {
        removeMonitors()
        message = nil
        recordingAction = action
        HotkeyManager.shared.stop()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
            return nil   // 录制期间消费事件，防止误触其他操作
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    func cancelRecording() {
        removeMonitors()
        recordingAction = nil
        HotkeyManager.shared.reloadAndReregister()
    }

    private func handleEvent(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        if event.type == .flagsChanged { return }   // 单独修饰键，忽略
        if event.keyCode == UInt16(kVK_Escape) { cancelRecording(); return }
        guard let binding = HotkeyBinding(event: event) else { return }
        finishRecording(action: action, newBinding: binding)
    }

    private func finishRecording(action: HotkeyAction, newBinding: HotkeyBinding) {
        removeMonitors()
        recordingAction = nil

        if let conflict = HotkeyStore.shared.conflictingAction(binding: newBinding, excludingAction: action) {
            message = (text: "与「\(conflict.label)」冲突，快捷键未更改。", isError: true)
            HotkeyManager.shared.reloadAndReregister()
            return
        }

        let oldBinding = HotkeyStore.shared.binding(for: action)
        HotkeyStore.shared.setBinding(newBinding, for: action)
        let failures = HotkeyManager.shared.reloadAndReregister()

        if failures.contains(action) {
            HotkeyStore.shared.setBinding(oldBinding, for: action)
            HotkeyManager.shared.reloadAndReregister()
            message = (text: "这个快捷键可能已被系统或其他 App 占用，已恢复原快捷键。", isError: false)
        }
    }

    private func removeMonitors() {
        if let m = localMonitor  { NSEvent.removeMonitor(m); localMonitor  = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }
}

// MARK: - 快捷键 Tab

private struct HotkeysTab: View {
    @StateObject private var recorder = HotkeyRecorder()
    @ObservedObject private var store = HotkeyStore.shared

    var body: some View {
        SettingsContentContainer(width: SettingsMetrics.hotkeysContentWidth) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSection(title: "快捷键") {
                    ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element) { index, action in
                        HotkeyRow(
                            action: action,
                            binding: store.binding(for: action),
                            isRecording: recorder.recordingAction == action,
                            isAnyRecording: recorder.recordingAction != nil,
                            onRecord: { recorder.startRecording(action) },
                            onRestoreDefault: {
                                HotkeyStore.shared.restoreDefault(for: action)
                                HotkeyManager.shared.reloadAndReregister()
                            }
                        )

                        if index < HotkeyAction.allCases.count - 1 {
                            SettingsDivider()
                        }
                    }
                }

                if recorder.recordingAction != nil {
                    Text("请按下新的快捷键。按 Esc 取消。")
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .padding(.top, 2)
                } else if let msg = recorder.message {
                    Text(msg.text)
                        .font(.system(size: 12))
                        .foregroundColor(msg.isError ? .red : .orange)
                        .padding(.top, 2)
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("全部恢复默认快捷键") {
                        HotkeyStore.shared.restoreDefaults()
                        HotkeyManager.shared.reloadAndReregister()
                    }
                    .controlSize(.regular)
                    .disabled(recorder.recordingAction != nil)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { recorder.cancelRecording() }
    }
}

private struct HotkeyRow: View {
    let action: HotkeyAction
    let binding: HotkeyBinding
    let isRecording: Bool
    let isAnyRecording: Bool
    let onRecord: () -> Void
    let onRestoreDefault: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(action.label)
                .font(.system(size: 13))
                .foregroundColor(Color(nsColor: .labelColor))
                .frame(width: 190, alignment: .leading)

            Text(isRecording ? "等待输入" : binding.displayString)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(isRecording ? .orange : Color(nsColor: .labelColor))
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)

            Button(isRecording ? "按下快捷键…" : "录制", action: onRecord)
                .controlSize(.small)
                .frame(width: 72)
                .disabled(isAnyRecording && !isRecording)
                .accessibilityHint("按下后按下新快捷键来录制，Esc 取消")

            Button(action: onRestoreDefault) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .regular))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(width: 34, height: 24)
            .disabled(isAnyRecording)
            .help("恢复默认")
            .accessibilityLabel("恢复默认")
            Spacer(minLength: 0)
        }
        .frame(width: SettingsMetrics.hotkeysContentWidth, height: 40, alignment: .leading)
    }
}

// MARK: - 权限

private struct PermissionsTab: View {
    @ObservedObject private var pm = PermissionsManager.shared

    var body: some View {
        SettingsContentContainer(width: SettingsMetrics.permissionsContentWidth) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Keystone2 需要以下权限来完成截图、OCR、快捷键监听和鼠标高亮功能。")
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: SettingsMetrics.permissionsContentWidth, alignment: .leading)

                SettingsSection(title: "系统权限") {
                    PermissionRow(
                        label: "屏幕录制",
                        status: pm.screenRecording,
                        detail: "用于截图、OCR 识别和屏幕标注。",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    )

                    SettingsDivider()

                    PermissionRow(
                        label: "辅助功能",
                        status: pm.accessibility,
                        detail: "用于全局快捷键、鼠标事件和鼠标高亮。",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    )
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("刷新权限状态") { pm.checkPermissions() }
                        .controlSize(.regular)
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { pm.checkPermissions() }
    }
}

private struct PermissionRow: View {
    let label: String
    let status: PermissionStatus
    let detail: String
    let settingsURL: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(nsColor: .labelColor))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
            }
            .frame(width: 360, alignment: .leading)
            Spacer(minLength: 0)

            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                    Text(status.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(Color(nsColor: .labelColor))
                        .frame(width: 52, alignment: .leading)
                }

                Button(status == .granted ? "打开设置" : "去设置") {
                    openSettings()
                }
                .controlSize(.small)
            }
            .frame(width: 168, alignment: .trailing)
        }
        .frame(width: SettingsMetrics.permissionsContentWidth, height: 52)
    }

    private func openSettings() {
        guard let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
