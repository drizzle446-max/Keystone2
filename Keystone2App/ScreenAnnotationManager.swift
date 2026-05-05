import AppKit

final class ScreenAnnotationManager {
    static let shared = ScreenAnnotationManager()
    private init() {}

    private(set) var isActive = false
    private var overlayControllersByScreen: [(screen: NSScreen, controller: ScreenAnnotationWindowController)] = []
    private var toolbarController: AnnotationToolbarWindowController?
    private var escMonitor: Any?
    private var mouseHighlightMonitor: Any?
    private var isPassthrough = false
    private var isMouseHighlightEnabled = false

    func startAnnotation() {
        if isActive { stopAnnotation(); return }

        guard CaptureFlowCoordinator.shared.begin("ScreenAnnotationManager") else { return }

        isActive = true
        isPassthrough = false
        isMouseHighlightEnabled = false

        var pairs: [(screen: NSScreen, controller: ScreenAnnotationWindowController)] = []
        for screen in NSScreen.screens {
            let overlay = ScreenAnnotationWindowController()
            overlay.onExit = { [weak self] in self?.stopAnnotation() }
            overlay.show(on: screen)
            pairs.append((screen: screen, controller: overlay))
        }
        overlayControllersByScreen = pairs

        // Toolbar on mouse screen, falling back to primary screen
        let toolbarScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let toolbar = AnnotationToolbarWindowController()
        toolbar.onToolSelected = { [weak self, weak toolbar] tool in
            self?.overlayControllersByScreen.forEach { $0.controller.annotationView?.setTool(tool) }
            self?.setPassthrough(false)
            toolbar?.setActiveTool(tool)
            self?.refocusActiveOverlay()
        }
        toolbar.onPassthroughChanged = { [weak self] enabled in
            self?.setPassthrough(enabled)
            self?.refocusActiveOverlay()
        }
        toolbar.onMouseHighlightChanged = { [weak self] enabled in
            self?.setMouseHighlight(enabled)
            self?.refocusActiveOverlay()
        }
        toolbar.onClear = { [weak self] in
            self?.overlayControllersByScreen.forEach { $0.controller.annotationView?.clearAnnotations() }
            self?.refocusActiveOverlay()
        }
        toolbar.onExit = { [weak self] in self?.stopAnnotation() }
        toolbar.show(on: toolbarScreen)
        toolbarController = toolbar

        // Global Esc monitor — catches Esc regardless of which window is key
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.stopAnnotation(); return nil }
            return event
        }
    }

    func stopAnnotation() {
        guard isActive else { return }
        isActive = false

        if let monitor = escMonitor { NSEvent.removeMonitor(monitor); escMonitor = nil }
        if let monitor = mouseHighlightMonitor { NSEvent.removeMonitor(monitor); mouseHighlightMonitor = nil }
        isPassthrough = false
        isMouseHighlightEnabled = false
        overlayControllersByScreen.forEach { $0.controller.dismiss() }
        overlayControllersByScreen = []
        toolbarController?.dismiss()
        toolbarController = nil

        CaptureFlowCoordinator.shared.end("ScreenAnnotationManager")
    }

    private func setPassthrough(_ enabled: Bool) {
        guard isActive else { return }
        isPassthrough = enabled
        overlayControllersByScreen.forEach { $0.controller.setPassthrough(enabled) }
        toolbarController?.setPassthrough(enabled)
    }

    private func setMouseHighlight(_ enabled: Bool) {
        guard isActive else { return }
        isMouseHighlightEnabled = enabled
        overlayControllersByScreen.forEach { $0.controller.setMouseHighlightEnabled(enabled) }
        toolbarController?.setMouseHighlight(enabled)
        if enabled {
            updateMouseHighlightLocation()
            installMouseHighlightMonitorIfNeeded()
        } else {
            if let monitor = mouseHighlightMonitor {
                NSEvent.removeMonitor(monitor)
                mouseHighlightMonitor = nil
            }
        }
    }

    private func refocusActiveOverlay() {
        let mouse = NSEvent.mouseLocation
        let pair = overlayControllersByScreen.first(where: { $0.screen.frame.contains(mouse) })
            ?? overlayControllersByScreen.first
        pair?.controller.refocusAnnotationView()
    }

    private func installMouseHighlightMonitorIfNeeded() {
        guard mouseHighlightMonitor == nil else { return }
        mouseHighlightMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMouseHighlightLocation()
            }
        }
    }

    private func updateMouseHighlightLocation() {
        guard isMouseHighlightEnabled else { return }
        let mouse = NSEvent.mouseLocation
        for (screen, controller) in overlayControllersByScreen {
            if screen.frame.contains(mouse) {
                controller.updateMouseHighlight(globalLocation: mouse)
            } else {
                controller.clearMouseHighlightDot()
            }
        }
    }
}
