import AppKit

final class PinManager {
    static let shared = PinManager()

    private var pinControllers: [PinWindowController] = []

    private init() {}

    @discardableResult
    func showPin(
        image: NSImage,
        screenFrame: NSRect? = nil
    ) -> PinWindowController {
        let pin = PinWindowController(image: image, screenFrame: screenFrame)
        pinControllers.append(pin)
        pin.onClose = { [weak self, weak pin] in
            guard let self, let pin else { return }
            self.pinControllers.removeAll { $0 === pin }
        }
        pin.show()
        return pin
    }
}
