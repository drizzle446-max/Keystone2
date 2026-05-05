import AppKit

enum OverlayStyle {
    case dimmed  // dark mask with transparent selection window (screenshot/pin)
    case clear   // no mask, selection border only (OCR)
}

// 接收键盘事件需要自定义 NSWindow，让 canBecomeKey 返回 true
private class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // Prevent AppKit from constraining the window to a single screen — needed
    // for secondary screens whose frame.origin is non-zero in global coordinates.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

private class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var style: OverlayStyle = .dimmed
    var cursor: NSCursor = .crosshair

    private var startPoint: NSPoint?
    private var currentRect: CGRect?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    // Allow the first click on a non-key overlay window to both activate it
    // and start the selection drag — no extra click needed when switching screens.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingAreaRef { removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    func applyCursor() { cursor.set() }

    override func cursorUpdate(with event: NSEvent) { applyCursor() }
    override func mouseEntered(with event: NSEvent) { applyCursor() }
    override func mouseMoved(with event: NSEvent) { applyCursor() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override func mouseDown(with event: NSEvent) {
        applyCursor()
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        applyCursor()
        guard let start = startPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(x: min(start.x, cur.x),
                             y: min(start.y, cur.y),
                             width: abs(cur.x - start.x),
                             height: abs(cur.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 5, rect.height > 5 else {
            onCancel?()
            return
        }
        onSelect?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .dimmed: drawDimmed()
        case .clear:  drawClear()
        }
    }

    private func drawDimmed() {
        let dark = NSColor.black.withAlphaComponent(0.4)
        if let rect = currentRect {
            dark.setFill()
            NSRect(x: 0,         y: rect.maxY,  width: bounds.width,            height: bounds.maxY - rect.maxY).fill()
            NSRect(x: 0,         y: 0,           width: bounds.width,            height: rect.minY).fill()
            NSRect(x: 0,         y: rect.minY,   width: rect.minX,               height: rect.height).fill()
            NSRect(x: rect.maxX, y: rect.minY,   width: bounds.maxX - rect.maxX, height: rect.height).fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()
        } else {
            dark.setFill()
            bounds.fill()
        }
    }

    private func drawClear() {
        guard let rect = currentRect else { return }
        let outerPath = NSBezierPath(rect: rect)
        outerPath.lineWidth = 2
        NSColor.black.withAlphaComponent(0.5).setStroke()
        outerPath.stroke()
        let innerPath = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        innerPath.lineWidth = 1
        NSColor.white.setStroke()
        innerPath.stroke()
    }
}

class ScreenshotOverlayWindowController: NSWindowController {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onInlineCopy: ((NSImage) -> Void)?
    var onInlineSave: ((NSImage) -> Void)?
    var onInlinePin: ((NSImage, NSRect) -> Void)?

    private let screenFrame: NSRect
    private var selectionView: SelectionView!
    private var cursorPushed = false

    // Custom crosshair with center circle — used only for OCR (.clear) style.
    // 25×25pt; arms stop before the circle; black outer + white inner for any background.
    private static let ocrSelectionCursor: NSCursor = {
        let size: CGFloat = 25
        let center: CGFloat = 12.5
        let armGap: CGFloat = 4
        let circleRadius: CGFloat = 3

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            func drawArm(from: NSPoint, to: NSPoint) {
                NSColor.black.setStroke()
                let outer = NSBezierPath(); outer.lineWidth = 2
                outer.move(to: from); outer.line(to: to); outer.stroke()
                NSColor.white.setStroke()
                let inner = NSBezierPath(); inner.lineWidth = 1
                inner.move(to: from); inner.line(to: to); inner.stroke()
            }
            drawArm(from: NSPoint(x: 0, y: center),
                    to:   NSPoint(x: center - armGap, y: center))
            drawArm(from: NSPoint(x: center + armGap, y: center),
                    to:   NSPoint(x: size, y: center))
            drawArm(from: NSPoint(x: center, y: 0),
                    to:   NSPoint(x: center, y: center - armGap))
            drawArm(from: NSPoint(x: center, y: center + armGap),
                    to:   NSPoint(x: center, y: size))

            let circleRect = CGRect(x: center - circleRadius, y: center - circleRadius,
                                    width: circleRadius * 2,  height: circleRadius * 2)
            let outerCircle = NSBezierPath(ovalIn: circleRect.insetBy(dx: -0.5, dy: -0.5))
            outerCircle.lineWidth = 2; NSColor.black.setStroke(); outerCircle.stroke()
            let innerCircle = NSBezierPath(ovalIn: circleRect)
            innerCircle.lineWidth = 1; NSColor.white.setStroke(); innerCircle.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }()

    init(screen: NSScreen, style: OverlayStyle = .dimmed) {
        screenFrame = screen.frame
        let win = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        win.backgroundColor = .clear
        win.isOpaque = false
        win.ignoresMouseEvents = false
        win.acceptsMouseMovedEvents = true

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.style = style
        view.cursor = (style == .clear) ? ScreenshotOverlayWindowController.ocrSelectionCursor : .crosshair
        win.contentView = view
        selectionView = view

        super.init(window: win)

        // Force the correct frame — AppKit may constrain borderless windows to
        // a single screen during init when the screen's origin is non-zero.
        win.setFrame(screen.frame, display: false)

        view.onSelect = { [weak self] rect in self?.onSelect?(rect) }
        view.onCancel = { [weak self] in self?.onCancel?() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        // Re-apply frame before showing — makeKeyAndOrderFront can trigger
        // constrainFrameRect, which may shift windows on secondary screens.
        window?.setFrame(screenFrame, display: false)
        // Activate first so the window can become key and receive cursor events
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(selectionView)
        window?.invalidateCursorRects(for: selectionView)
        selectionView.applyCursor()   // immediate set before first mouse-moved event
        selectionView.cursor.push()   // push onto cursor stack as backup
        cursorPushed = true
    }

    func dismiss() {
        popCursorIfNeeded()
        window?.orderOut(nil)
    }

    func beginInlineEditing(image: NSImage, selectionRect: NSRect,
                            fullSnapshot: NSImage, screen: NSScreen) {
        guard let window else { return }
        popCursorIfNeeded()
        let editor = InlineScreenshotEditorView(frame: NSRect(origin: .zero, size: window.frame.size),
                                                image: image,
                                                selectionRect: selectionRect,
                                                fullSnapshot: fullSnapshot,
                                                screen: screen)
        editor.onCopy = { [weak self] image in self?.onInlineCopy?(image) }
        editor.onSave = { [weak self] image in self?.onInlineSave?(image) }
        editor.onPin = { [weak self] image, frame in self?.onInlinePin?(image, frame) }
        editor.onCancel = { [weak self] in self?.onCancel?() }
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
    }

    func temporarilyHideForCapture() {
        popCursorIfNeeded()
        window?.orderOut(nil)
    }

    private func popCursorIfNeeded() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}
