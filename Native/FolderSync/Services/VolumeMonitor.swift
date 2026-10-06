@preconcurrency import AppKit

@MainActor
final class VolumeMonitor {
    private var observers: [NSObjectProtocol] = []
    private let onVolumeAvailable: () -> Void

    init(onVolumeAvailable: @escaping () -> Void) {
        self.onVolumeAvailable = onVolumeAvailable
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onVolumeAvailable() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onVolumeAvailable() }
            }
        ]
    }

}
