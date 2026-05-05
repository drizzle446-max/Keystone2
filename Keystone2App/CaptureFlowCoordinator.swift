final class CaptureFlowCoordinator {
    static let shared = CaptureFlowCoordinator()
    private init() {}

    private(set) var activeOwner: String?

    func begin(_ owner: String) -> Bool {
        guard activeOwner == nil else { return false }
        activeOwner = owner
        return true
    }

    func end(_ owner: String) {
        if activeOwner == owner { activeOwner = nil }
    }
}
