import CoreServices
import Foundation

final class FolderWatcher {
    private let folder: URL
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var debounceWorkItem: DispatchWorkItem?
    private var hasSecurityScope = false

    init(folder: URL, onChange: @escaping () -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    deinit { stop() }

    func start() -> Bool {
        hasSecurityScope = folder.startAccessingSecurityScopedResource()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.handleEvent,
            &context,
            [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )
        guard let stream else { return false }
        FSEventStreamSetDispatchQueue(stream, .main)
        return FSEventStreamStart(stream)
    }

    func stop() {
        debounceWorkItem?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        if hasSecurityScope { folder.stopAccessingSecurityScopedResource() }
        hasSecurityScope = false
    }

    private func scheduleSync() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private static let handleEvent: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().scheduleSync()
    }
}
