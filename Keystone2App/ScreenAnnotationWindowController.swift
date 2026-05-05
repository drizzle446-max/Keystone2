import AppKit

private class AnnotationOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

final class ScreenAnnotationWindowController: NSObject {
    private(set) var annotationView: ScreenAnnotationView?
    private var overlayWindow: AnnotationOverlayWindow?

    var onExit: (() -> Void)?

    func show(on screen: NSScreen) {
        let win = AnnotationOverlayWindow(
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
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false

        let view = ScreenAnnotationView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onExit = { [weak self] in self?.onExit?() }
        win.contentView = view
        annotationView = view
        overlayWindow = win

        // Force the correct frame — same constrainFrameRect issue as overlay windows.
        win.setFrame(screen.frame, display: false)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    func refocusAnnotationView() {
        overlayWindow?.makeKey()
        if let view = annotationView {
            overlayWindow?.makeFirstResponder(view)
        }
    }

    func dismiss() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        annotationView = nil
    }

    func setPassthrough(_ enabled: Bool) {
        overlayWindow?.ignoresMouseEvents = enabled
    }

    func setMouseHighlightEnabled(_ enabled: Bool) {
        annotationView?.setMouseHighlightEnabled(enabled)
    }

    func updateMouseHighlight(globalLocation: NSPoint) {
        guard let overlayWindow, let annotationView else { return }
        let windowPoint = overlayWindow.convertPoint(fromScreen: globalLocation)
        let viewPoint = annotationView.convert(windowPoint, from: nil)
        annotationView.updateMouseHighlightLocation(viewPoint)
    }

    func clearMouseHighlightDot() {
        annotationView?.clearMouseHighlightDot()
    }
}
