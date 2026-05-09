import AppKit
import CoreGraphics
import UniformTypeIdentifiers

final class ScreenshotManager {
    static let shared = ScreenshotManager()
    private init() {}

    private enum Mode { case editor, copy, pin }

    private var overlayControllers: [ScreenshotOverlayWindowController] = []
    private var activeOverlayController: ScreenshotOverlayWindowController?

    func takeScreenshot()        { startSelection(mode: .editor) }
    func takeScreenshotAndCopy() { startSelection(mode: .copy) }
    func takeScreenshotAndPin()  { startSelection(mode: .pin) }

    private func startSelection(mode: Mode) {
        guard CaptureFlowCoordinator.shared.begin("ScreenshotManager") else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            CaptureFlowCoordinator.shared.end("ScreenshotManager")
            return
        }

        var controllers: [ScreenshotOverlayWindowController] = []
        for screen in screens {
            let overlay = ScreenshotOverlayWindowController(screen: screen)
            overlay.onSelect = { [weak self, weak overlay] rect in
                guard let overlay else { return }
                self?.handleSelection(rect: rect, screen: screen, mode: mode, selectedOverlay: overlay)
            }
            overlay.onCancel = { [weak self] in
                self?.dismissAllOverlays()
                CaptureFlowCoordinator.shared.end("ScreenshotManager")
            }
            controllers.append(overlay)
        }
        overlayControllers = controllers
        overlayControllers.forEach { $0.show() }
    }

    private func dismissAllOverlays() {
        overlayControllers.forEach { $0.dismiss() }
        overlayControllers = []
        activeOverlayController = nil
    }

    private func handleSelection(rect: CGRect, screen: NSScreen, mode: Mode,
                                  selectedOverlay: ScreenshotOverlayWindowController) {
        if mode == .editor {
            overlayControllers.forEach { $0.temporarilyHideForCapture() }
            activeOverlayController = selectedOverlay
        } else {
            dismissAllOverlays()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.captureAndDispatch(rect: rect, screen: screen, mode: mode)
        }
    }

    private func captureAndDispatch(rect: CGRect, screen: NSScreen, mode: Mode) {
        let scale = screen.backingScaleFactor

        // Pixel-align selection to nearest pixel boundary so the capture rect
        // maps to exact pixel coordinates (avoids fractional-point capture artifacts).
        let captureRect: CGRect = {
            let minX = (rect.minX * scale).rounded() / scale
            let minY = (rect.minY * scale).rounded() / scale
            let maxX = (rect.maxX * scale).rounded() / scale
            let maxY = (rect.maxY * scale).rounded() / scale
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }()

        guard let cgImage = captureScreen(rect: captureRect, screen: screen) else {
            if PermissionsManager.hasAttemptedScreenCapture {
                PermissionsManager.shared.showScreenRecordingAlertIfNeeded(feature: "截图")
            }
            PermissionsManager.hasAttemptedScreenCapture = true
            dismissAllOverlays()
            CaptureFlowCoordinator.shared.end("ScreenshotManager")
            return
        }

        // Use cgImage pixel dimensions as the definitive point size.
        // captureRect.width/height may be non-integer points (e.g. 222.5 on 2× Retina),
        // which causes AppKit to expand the window by 1pt on each non-integer axis,
        // creating a size mismatch with the image and visible stretching.
        let pointW = (CGFloat(cgImage.width) / scale).rounded()
        let pointH = (CGFloat(cgImage.height) / scale).rounded()
        let image = NSImage(cgImage: cgImage, size: NSSize(width: pointW, height: pointH))

        switch mode {
        case .editor:
            guard let overlayController = activeOverlayController else {
                CaptureFlowCoordinator.shared.end("ScreenshotManager")
                return
            }
            // Capture full screen snapshot (all overlays already hidden by handleSelection)
            guard let fullCG = captureScreen(rect: NSRect(origin: .zero, size: screen.frame.size), screen: screen) else {
                PermissionsManager.shared.showScreenRecordingAlertIfNeeded(feature: "截图")
                dismissAllOverlays()
                CaptureFlowCoordinator.shared.end("ScreenshotManager")
                return
            }
            let fullSnapshot = NSImage(cgImage: fullCG, size: screen.frame.size)
            overlayController.onInlineCopy = { [weak self] image in
                self?.finishInlineCopy(image)
            }
            overlayController.onInlineSave = { [weak self] image in
                self?.finishInlineSave(image)
            }
            overlayController.onInlinePin = { [weak self] image, frame in
                self?.finishInlinePin(image, pinFrame: frame)
            }
            overlayController.beginInlineEditing(
                image: image,
                selectionRect: captureRect,
                fullSnapshot: fullSnapshot,
                screen: screen
            )
            return
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        case .pin:
            // Round origin to integer points so the full frame (origin + integer size)
            // has all-integer bounds — AppKit will not expand an all-integer rect.
            // This guarantees: pin window size == NSImage size (no stretching).
            let pinX = (captureRect.minX + screen.frame.minX).rounded()
            let pinY = (captureRect.minY + screen.frame.minY).rounded()
            let pinFrame = NSRect(x: pinX, y: pinY, width: pointW, height: pointH)

            PinManager.shared.showPin(image: image, screenFrame: pinFrame)
        }

        CaptureFlowCoordinator.shared.end("ScreenshotManager")
    }

    private func finishInlineCopy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        dismissAllOverlays()
        CaptureFlowCoordinator.shared.end("ScreenshotManager")
    }

    private func finishInlineSave(_ image: NSImage) {
        dismissAllOverlays()
        CaptureFlowCoordinator.shared.end("ScreenshotManager")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Self.defaultScreenshotFileName()
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            guard let data = image.pngData() else { return }
            do {
                try data.write(to: url)
            } catch { }
        }
    }

    private static func defaultScreenshotFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return "screenshot_\(formatter.string(from: date))"
    }

    private func finishInlinePin(_ image: NSImage, pinFrame: NSRect) {
        PinManager.shared.showPin(image: image, screenFrame: pinFrame)
        dismissAllOverlays()
        CaptureFlowCoordinator.shared.end("ScreenshotManager")
    }

    // MARK: - 坐标转换 + 截图

    private func captureScreen(rect: CGRect, screen: NSScreen) -> CGImage? {
        // Step 1: view-local → global AppKit（加入 screen.frame.origin）
        let globalAppKit = CGRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: rect.origin.y + screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )

        // Step 2: global AppKit → CG 全局坐标（原点左上，Y 向下）
        let primaryH = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgRect = CGRect(
            x: globalAppKit.origin.x,
            y: primaryH - globalAppKit.origin.y - globalAppKit.height,
            width: globalAppKit.width,
            height: globalAppKit.height
        )

        let cgImage = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
        guard CGPreflightScreenCaptureAccess() else { return nil }
        return cgImage
    }
}
