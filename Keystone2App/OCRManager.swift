import AppKit
import CoreGraphics
import Vision
import UserNotifications

final class OCRManager {
    static let shared = OCRManager()
    private init() {}

    private var overlayControllers: [ScreenshotOverlayWindowController] = []

    func startOCR() {
        guard CaptureFlowCoordinator.shared.begin("OCRManager") else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            CaptureFlowCoordinator.shared.end("OCRManager")
            return
        }

        var controllers: [ScreenshotOverlayWindowController] = []
        for screen in screens {
            let overlay = ScreenshotOverlayWindowController(screen: screen, style: .clear)
            overlay.onSelect = { [weak self] rect in
                self?.handleSelection(rect: rect, screen: screen)
            }
            overlay.onCancel = { [weak self] in
                self?.dismissAllOverlays()
                CaptureFlowCoordinator.shared.end("OCRManager")
            }
            controllers.append(overlay)
        }
        overlayControllers = controllers
        overlayControllers.forEach { $0.show() }
    }

    private func dismissAllOverlays() {
        overlayControllers.forEach { $0.dismiss() }
        overlayControllers = []
    }

    private func handleSelection(rect: CGRect, screen: NSScreen) {
        dismissAllOverlays()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.captureAndRecognize(rect: rect, screen: screen)
        }
    }

    private func captureAndRecognize(rect: CGRect, screen: NSScreen) {
        guard let cgImage = captureScreen(rect: rect, screen: screen) else {
            if PermissionsManager.hasAttemptedScreenCapture {
                PermissionsManager.shared.showScreenRecordingAlertIfNeeded(feature: "OCR")
            }
            PermissionsManager.hasAttemptedScreenCapture = true
            CaptureFlowCoordinator.shared.end("OCRManager")
            return
        }

        let request = VNRecognizeTextRequest { [weak self] request, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(request: request, error: error)
            }
        }
        request.recognitionLevel = .accurate

        // Query supported languages via instance method (macOS 13+); fall back to full list
        let preferredLangs = ["zh-Hans", "en-US"]
        let supported = (try? request.supportedRecognitionLanguages()) ?? preferredLangs
        let langList = preferredLangs.filter { supported.contains($0) }
        request.recognitionLanguages = langList.isEmpty ? preferredLangs : langList
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    CaptureFlowCoordinator.shared.end("OCRManager")
                }
            }
        }
    }

    private func handleRecognitionResult(request: VNRequest, error: Error?) {
        defer { CaptureFlowCoordinator.shared.end("OCRManager") }

        if error != nil { return }

        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        guard !text.isEmpty else { return }

        // Only write clipboard on non-empty success result
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showSuccessNotification(charCount: text.count)
    }

    private func captureScreen(rect: CGRect, screen: NSScreen) -> CGImage? {
        let globalAppKit = CGRect(
            x: rect.origin.x + screen.frame.origin.x,
            y: rect.origin.y + screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
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

    private func showSuccessNotification(charCount: Int) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard settings.authorizationStatus == .authorized else { return }
                let content = UNMutableNotificationContent()
                content.title = "OCR 完成"
                content.body = "已复制 \(charCount) 个字符到剪贴板"
                let notifRequest = UNNotificationRequest(
                    identifier: "OCRManager-\(Date().timeIntervalSince1970)",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(notifRequest)
            }
        }
    }
}
