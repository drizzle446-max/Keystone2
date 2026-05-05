import AppKit

private class ToolbarPanel: NSPanel {
    var onEscKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscKey?() } else { super.keyDown(with: event) }
    }
}

// NSButton subclass with closure-based action handling
private class ActionButton: NSButton {
    var onAction: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        target = self
        action = #selector(tapped)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() { onAction?() }
}

final class AnnotationToolbarWindowController: NSObject {
    private var panel: ToolbarPanel?
    private var toolButtons: [AnnotationKind: ActionButton] = [:]
    private var passthroughButton: ActionButton?
    private var mouseHighlightButton: ActionButton?
    private var isPassthrough = false
    private var isMouseHighlightEnabled = false

    var onToolSelected: ((AnnotationKind) -> Void)?
    var onPassthroughChanged: ((Bool) -> Void)?
    var onMouseHighlightChanged: ((Bool) -> Void)?
    var onClear: (() -> Void)?
    var onExit: (() -> Void)?

    func show(on screen: NSScreen) {
        let width: CGFloat = 418
        let height: CGFloat = 44
        // visibleFrame excludes menu bar / notch area
        let x = screen.visibleFrame.minX + (screen.visibleFrame.width - width) / 2
        let y = screen.visibleFrame.maxY - height - 12

        let p = ToolbarPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.onEscKey = { [weak self] in self?.onExit?() }
        panel = p

        let content = buildToolbarView(size: NSSize(width: width, height: height))
        p.contentView = content
        p.orderFront(nil)

        highlightTool(.pen)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        toolButtons.removeAll()
        passthroughButton = nil
        mouseHighlightButton = nil
    }

    func setActiveTool(_ tool: AnnotationKind) {
        highlightTool(tool)
    }

    func setPassthrough(_ enabled: Bool) {
        isPassthrough = enabled
        updatePassthroughButton()
    }

    func setMouseHighlight(_ enabled: Bool) {
        isMouseHighlightEnabled = enabled
        updateMouseHighlightButton()
    }

    // MARK: - UI construction

    private func buildToolbarView(size: NSSize) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.90).cgColor

        let btnH: CGFloat = 32
        let y = (size.height - btnH) / 2
        var x: CGFloat = 6

        let toolDefs: [(String, AnnotationKind, CGFloat)] = [
            ("画笔", .pen, 40),
            ("箭头", .arrow, 40),
            ("矩形", .rectangle, 40),
            ("高亮", .highlight, 40),
        ]

        for (label, tool, w) in toolDefs {
            let btn = makeButton(label, frame: NSRect(x: x, y: y, width: w, height: btnH))
            btn.onAction = { [weak self] in self?.onToolSelected?(tool) }
            toolButtons[tool] = btn
            container.addSubview(btn)
            x += w + 4
        }

        // Separator
        let sep = NSView(frame: NSRect(x: x + 2, y: 8, width: 1, height: size.height - 16))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        container.addSubview(sep)
        x += 10

        let passthrough = makeButton("穿透", frame: NSRect(x: x, y: y, width: 44, height: btnH))
        passthrough.onAction = { [weak self] in
            guard let self else { return }
            setPassthrough(!isPassthrough)
            onPassthroughChanged?(isPassthrough)
        }
        passthroughButton = passthrough
        container.addSubview(passthrough)
        x += 48

        let mouseHighlight = makeButton("鼠标", frame: NSRect(x: x, y: y, width: 44, height: btnH))
        mouseHighlight.onAction = { [weak self] in
            guard let self else { return }
            setMouseHighlight(!isMouseHighlightEnabled)
            onMouseHighlightChanged?(isMouseHighlightEnabled)
        }
        mouseHighlightButton = mouseHighlight
        container.addSubview(mouseHighlight)
        x += 48

        let actionDefs: [(String, CGFloat)] = [("清空", 44), ("退出", 40)]
        for (i, (label, w)) in actionDefs.enumerated() {
            let btn = makeButton(label, frame: NSRect(x: x, y: y, width: w, height: btnH))
            if i == 0 { btn.onAction = { [weak self] in self?.onClear?() } }
            else       { btn.onAction = { [weak self] in self?.onExit?() } }
            container.addSubview(btn)
            x += w + 4
        }

        return container
    }

    private func makeButton(_ title: String, frame: NSRect) -> ActionButton {
        let btn = ActionButton(frame: frame)
        let attr = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        ])
        btn.attributedTitle = attr
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        return btn
    }

    private func highlightTool(_ tool: AnnotationKind) {
        for (t, btn) in toolButtons {
            btn.layer?.backgroundColor = (t == tool)
                ? NSColor.white.withAlphaComponent(0.22).cgColor
                : NSColor.clear.cgColor
        }
    }

    private func updatePassthroughButton() {
        guard let btn = passthroughButton else { return }
        let title = isPassthrough ? "标注" : "穿透"
        btn.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        ])
        btn.layer?.backgroundColor = isPassthrough
            ? NSColor.systemBlue.withAlphaComponent(0.75).cgColor
            : NSColor.clear.cgColor
    }

    private func updateMouseHighlightButton() {
        guard let btn = mouseHighlightButton else { return }
        btn.layer?.backgroundColor = isMouseHighlightEnabled
            ? NSColor.systemYellow.withAlphaComponent(0.30).cgColor
            : NSColor.clear.cgColor
    }
}
