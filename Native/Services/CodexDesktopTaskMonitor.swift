import Foundation
import CoreServices

enum CodexDesktopTaskMonitorDiagnostic: Equatable, Sendable {
    case sessionsRootUnavailable(URL)
    case transcriptUnreadable(URL)
    case overlongRecordDiscarded(URL, byteLimit: Int)
}

final class CodexDesktopTaskMonitorCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?

    init(_ cancellation: @escaping @Sendable () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        let action = lock.withLock {
            defer { cancellation = nil }
            return cancellation
        }
        action?()
    }

    deinit {
        cancel()
    }
}

enum CodexDesktopTaskScan: Sendable {
    case all
    case paths(Set<URL>, includeActive: Bool = false)

    func merging(_ other: Self) -> Self {
        if case let .paths(current, currentIncludesActive) = self,
           case let .paths(incoming, incomingIncludesActive) = other {
            return .paths(current.union(incoming), includeActive: currentIncludesActive || incomingIncludesActive)
        }
        return .all
    }
}

private final class CodexDesktopTaskMonitorFSEventWatcher: @unchecked Sendable {
    private static let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
        guard count > 0, let info else { return }
        let watcher = Unmanaged<CodexDesktopTaskMonitorFSEventWatcher>
            .fromOpaque(info)
            .takeUnretainedValue()
        let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let recoveryFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        let directoryChanges = UInt32(kFSEventStreamEventFlagItemCreated
            | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
        var changed: Set<URL> = []
        for index in 0..<count {
            let flag = flags[index]
            if flag & recoveryFlags != 0 ||
                (flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 && flag & directoryChanges != 0) {
                watcher.requestScan(.all)
                return
            }
            let url = URL(fileURLWithPath: String(cString: paths[index])).standardizedFileURL
            if url.pathExtension == "jsonl", let relativePath = watcher.relativePath(for: url) {
                changed.insert(watcher.rootURL.appendingPathComponent(relativePath))
            }
        }
        if !changed.isEmpty { watcher.requestScan(.paths(changed)) }
    }

    private let tick: @MainActor @Sendable (CodexDesktopTaskScan) -> Void
    private let rootURL: URL
    private let watchedRootPrefix: String
    private var stream: FSEventStreamRef?

    init?(rootURL: URL, tick: @escaping @MainActor @Sendable (CodexDesktopTaskScan) -> Void) {
        self.tick = tick
        self.rootURL = rootURL
        let watchedRoot = rootURL.resolvingSymlinksInPath()
        watchedRootPrefix = watchedRoot.path + "/"
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            [watchedRoot.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot
            )
        ) else {
            return nil
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return nil
        }
    }

    func cancel() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        cancel()
    }

    private func relativePath(for url: URL) -> String? {
        let path = url.path
        if path.hasPrefix(watchedRootPrefix) {
            return String(path.dropFirst(watchedRootPrefix.count))
        }
        let logicalRootPrefix = rootURL.path + "/"
        guard path.hasPrefix(logicalRootPrefix) else { return nil }
        return String(path.dropFirst(logicalRootPrefix.count))
    }

    private func requestScan(_ scan: CodexDesktopTaskScan) {
        Task { @MainActor [tick] in tick(scan) }
    }
}

private final class CodexDesktopTaskMonitorPollingTimer: @unchecked Sendable {
    private let timer: Timer

    @MainActor
    init(interval: TimeInterval, tick: @escaping @MainActor @Sendable () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    func cancel() {
        Task { @MainActor [timer] in
            timer.invalidate()
        }
    }
}

// All mutable parser/file state is confined to `queue`; only Sendable output
// values cross back to the main-actor lifecycle wrapper.
private final class CodexDesktopTaskMonitorWorker: @unchecked Sendable {
    typealias Discovery = @Sendable (URL) throws -> [URL]
    typealias ReadObserver = @Sendable (UInt64, Int) -> Void

    enum Output: Sendable {
        case events([DesktopCodexTaskLifecycleEvent])
        case diagnostic(CodexDesktopTaskMonitorDiagnostic)
    }

    private struct FileIdentity: Equatable {
        let system: UInt64
        let file: UInt64
    }

    private struct FileSnapshot {
        let identity: FileIdentity
        let byteCount: UInt64
        let modificationDate: Date
    }

    private struct TranscriptState {
        var identity: FileIdentity
        var offset: UInt64
        var parser: DesktopCodexTaskParser
        var trailingData: Data
        var modificationDate: Date
    }

    private static let replacementAnchorByteCount = 64 * 1_024
    private static let initialMetadataProbeByteCount = 64 * 1_024
    // Only recover work that was active immediately around app launch. A
    // transcript without a terminal event can otherwise make an old task look
    // active forever and inflate the shared phone task count after relaunch.
    private static let initialTaskRecoveryLookback: TimeInterval = 15 * 60

    private let queue = DispatchQueue(label: "CodexDesktopTaskMonitor.scan", qos: .utility)
    private let sessionsRootURL: URL
    private let discoverTranscripts: Discovery
    private let onRead: ReadObserver
    private var transcripts: [URL: TranscriptState] = [:]
    private var activeTranscriptURLs: Set<URL> = []
    private var isInitialDiscovery = true

    init(sessionsRootURL: URL, discoverTranscripts: @escaping Discovery, onRead: @escaping ReadObserver) {
        self.sessionsRootURL = sessionsRootURL
        self.discoverTranscripts = discoverTranscripts
        self.onRead = onRead
    }

    func start(deliver: @escaping @Sendable ([Output]) -> Void) {
        queue.async { [self] in
            transcripts.removeAll()
            activeTranscriptURLs.removeAll()
            isInitialDiscovery = true
            deliver(scan())
            isInitialDiscovery = false
        }
    }

    func requestScan(_ scope: CodexDesktopTaskScan, deliver: @escaping @Sendable ([Output]) -> Void) {
        queue.async { [self] in
            switch scope {
            case .all: deliver(scan())
            case let .paths(paths, includeActive):
                deliver(scan(includeActive ? paths.union(activeTranscriptURLs) : paths))
            }
        }
    }

    private func scan(_ paths: Set<URL>) -> [Output] {
        var outputs: [Output] = []
        let rootPrefix = sessionsRootURL.path + "/"
        for url in paths.sorted(by: { $0.path < $1.path }) where url.path.hasPrefix(rootPrefix) {
            let relativePath = url.path.dropFirst(rootPrefix.count)
            guard !relativePath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { continue }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                inspect(url, outputs: &outputs)
            } else {
                abandonTranscript(at: url, outputs: &outputs)
            }
        }
        return outputs
    }

    func reset() {
        queue.async { [self] in
            transcripts.removeAll()
            activeTranscriptURLs.removeAll()
        }
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            queue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func scan() -> [Output] {
        var outputs: [Output] = []
        let discovered: [URL]
        do {
            discovered = try discoverTranscripts(sessionsRootURL)
                .map(\.standardizedFileURL)
                .sorted { $0.path < $1.path }
        } catch {
            outputs.append(.diagnostic(.sessionsRootUnavailable(sessionsRootURL)))
            return outputs
        }

        let discoveredSet = Set(discovered)
        let removedURLs = transcripts.keys
            .filter { !discoveredSet.contains($0) }
            .sorted { $0.path < $1.path }
        for url in removedURLs {
            abandonTranscript(at: url, outputs: &outputs)
        }
        for url in discovered {
            inspect(url, outputs: &outputs)
        }
        return outputs
    }

    private func inspect(_ url: URL, outputs: inout [Output]) {
        defer {
            if let state = transcripts[url], !state.parser.activeTaskIDs.isEmpty {
                activeTranscriptURLs.insert(url)
            } else {
                activeTranscriptURLs.remove(url)
            }
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            abandonTranscript(at: url, outputs: &outputs)
            outputs.append(.diagnostic(.transcriptUnreadable(url)))
            return
        }

        guard let byteCount = (attributes[.size] as? NSNumber)?.uint64Value,
              let system = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let file = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let modificationDate = attributes[.modificationDate] as? Date else {
            abandonTranscript(at: url, outputs: &outputs)
            outputs.append(.diagnostic(.transcriptUnreadable(url)))
            return
        }

        let snapshot = FileSnapshot(
            identity: FileIdentity(system: system, file: file),
            byteCount: byteCount,
            modificationDate: modificationDate
        )
        if var state = transcripts[url], state.identity == snapshot.identity, snapshot.byteCount >= state.offset {
            if byteCount == state.offset, modificationDate == state.modificationDate { return }
            guard let anchorMatches = replacementAnchorMatches(url: url, state: state) else {
                abandonTranscript(at: url, outputs: &outputs)
                outputs.append(.diagnostic(.transcriptUnreadable(url)))
                return
            }
            guard anchorMatches else {
                abandonTranscript(at: url, outputs: &outputs)
                replaceState(for: url, snapshot: snapshot, outputs: &outputs)
                return
            }
            guard readAppend(from: url, byteCount: byteCount, state: &state, outputs: &outputs) else {
                publishTerminalEvents(for: state.parser, outputs: &outputs)
                transcripts.removeValue(forKey: url)
                return
            }
            state.modificationDate = modificationDate
            transcripts[url] = state
            return
        }

        abandonTranscript(at: url, outputs: &outputs)
        replaceState(for: url, snapshot: snapshot, outputs: &outputs)
    }

    private func replaceState(for url: URL, snapshot: FileSnapshot, outputs: inout [Output]) {
        let restoresInitialTasks = isInitialDiscovery
            && Date().timeIntervalSince(snapshot.modificationDate) <= Self.initialTaskRecoveryLookback
        let initialOffset = isInitialDiscovery && !restoresInitialTasks ? snapshot.byteCount : 0
        guard let trailingData = readReplacementAnchor(from: url, through: initialOffset) else {
            transcripts.removeValue(forKey: url)
            outputs.append(.diagnostic(.transcriptUnreadable(url)))
            return
        }
        var state = TranscriptState(
            identity: snapshot.identity,
            offset: initialOffset,
            parser: DesktopCodexTaskParser(transcriptID: relativeTranscriptID(for: url)),
            trailingData: trailingData,
            modificationDate: snapshot.modificationDate
        )
        if isInitialDiscovery,
           !restoresInitialTasks,
           !primeInitialMetadata(from: url, byteCount: snapshot.byteCount, parser: &state.parser) {
            transcripts.removeValue(forKey: url)
            outputs.append(.diagnostic(.transcriptUnreadable(url)))
            return
        }
        guard readAppend(
            from: url,
            byteCount: snapshot.byteCount,
            state: &state,
            outputs: &outputs,
            publishesEvents: !isInitialDiscovery
        ) else {
            publishTerminalEvents(for: state.parser, outputs: &outputs)
            transcripts.removeValue(forKey: url)
            return
        }
        if restoresInitialTasks, state.parser.restoresActiveTasksOnStartup {
            // Stable Codex session transcripts contain sequential root turns.
            // If an interrupted turn has no terminal record, only restore the
            // newest active turn on startup; later scans still reconcile turns
            // incrementally through `updateActiveDesktopTasks`.
            let activeIDs = state.parser.hasStableSessionID
                ? Array(state.parser.activeTaskIDsInStartOrder.suffix(1))
                : state.parser.activeTaskIDs
                    .sorted { ($0.transcriptID, $0.turnID) < ($1.transcriptID, $1.turnID) }
            let activeEvents = activeIDs
                .map(DesktopCodexTaskLifecycleEvent.started)
            if !activeEvents.isEmpty { outputs.append(.events(activeEvents)) }
        }
        transcripts[url] = state
    }

    private func primeInitialMetadata(
        from url: URL,
        byteCount: UInt64,
        parser: inout DesktopCodexTaskParser
    ) -> Bool {
        let probeByteCount = Int(min(UInt64(Self.initialMetadataProbeByteCount), byteCount))
        guard probeByteCount > 0 else { return true }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: probeByteCount), data.count == probeByteCount else {
                return false
            }
            onRead(0, data.count)
            parser.primeInitialMetadata(from: data)
            return true
        } catch {
            return false
        }
    }

    private func readAppend(
        from url: URL,
        byteCount: UInt64,
        state: inout TranscriptState,
        outputs: inout [Output],
        publishesEvents: Bool = true
    ) -> Bool {
        guard byteCount > state.offset else { return true }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: state.offset)
            while state.offset < byteCount {
                let requestedCount = Int(min(UInt64(CodexDesktopTaskMonitor.maximumReadByteCount), byteCount - state.offset))
                guard let data = try handle.read(upToCount: requestedCount), !data.isEmpty else {
                    outputs.append(.diagnostic(.transcriptUnreadable(url)))
                    return false
                }
                onRead(state.offset, data.count)
                state.offset += UInt64(data.count)
                state.trailingData.append(data)
                if state.trailingData.count > Self.replacementAnchorByteCount {
                    state.trailingData.removeFirst(state.trailingData.count - Self.replacementAnchorByteCount)
                }
                let previousDiscardCount = state.parser.discardedOverlongRecordCount
                let events = state.parser.consume(data)
                let discardCount = state.parser.discardedOverlongRecordCount - previousDiscardCount
                for _ in 0..<discardCount {
                    outputs.append(.diagnostic(.overlongRecordDiscarded(
                        url,
                        byteLimit: DesktopCodexTaskParser.maximumIncompleteRecordByteCount
                    )))
                }
                if publishesEvents, !events.isEmpty { outputs.append(.events(events)) }
            }
            return true
        } catch {
            outputs.append(.diagnostic(.transcriptUnreadable(url)))
            return false
        }
    }

    private func replacementAnchorMatches(url: URL, state: TranscriptState) -> Bool? {
        guard !state.trailingData.isEmpty else { return true }
        guard let currentAnchor = readReplacementAnchor(from: url, through: state.offset) else { return nil }
        return currentAnchor == state.trailingData
    }

    // The trailing 64 KiB anchor keeps replacement checks bounded. Rewrites
    // preserving that exact consumed suffix are outside this bounded guarantee.
    private func readReplacementAnchor(from url: URL, through byteCount: UInt64) -> Data? {
        guard byteCount > 0 else { return Data() }
        let count = Int(min(UInt64(Self.replacementAnchorByteCount), byteCount))
        let offset = byteCount - UInt64(count)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: count), data.count == count else { return nil }
            onRead(offset, data.count)
            return data
        } catch {
            return nil
        }
    }

    private func abandonTranscript(at url: URL, outputs: inout [Output]) {
        activeTranscriptURLs.remove(url)
        guard let state = transcripts.removeValue(forKey: url) else { return }
        publishTerminalEvents(for: state.parser, outputs: &outputs)
    }

    private func publishTerminalEvents(for parser: DesktopCodexTaskParser, outputs: inout [Output]) {
        let events = parser.activeTaskIDs
            .sorted { ($0.transcriptID, $0.turnID) < ($1.transcriptID, $1.turnID) }
            .map(DesktopCodexTaskLifecycleEvent.completed)
        if !events.isEmpty { outputs.append(.events(events)) }
    }

    private func relativeTranscriptID(for url: URL) -> String {
        let rootPath = sessionsRootURL.path.hasSuffix("/") ? sessionsRootURL.path : sessionsRootURL.path + "/"
        guard url.path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(url.path.dropFirst(rootPath.count))
    }
}

@MainActor
final class CodexDesktopTaskMonitor {
    typealias Discovery = @Sendable (URL) throws -> [URL]
    typealias Schedule = @MainActor @Sendable (URL, @escaping @MainActor @Sendable (CodexDesktopTaskScan) -> Void) -> CodexDesktopTaskMonitorCancellation
    typealias ReadObserver = @Sendable (UInt64, Int) -> Void

    nonisolated static let maximumReadByteCount = 64 * 1_024

    private let worker: CodexDesktopTaskMonitorWorker
    private let sessionsRootURL: URL
    private let schedule: Schedule
    private let onEvents: ([DesktopCodexTaskLifecycleEvent]) -> Void
    private let onDiagnostic: (CodexDesktopTaskMonitorDiagnostic) -> Void
    private var scheduledScan: CodexDesktopTaskMonitorCancellation?
    private var activePollingTimer: CodexDesktopTaskMonitorPollingTimer?
    private var activeDesktopTaskIDs: Set<DesktopCodexTaskID> = []
    private var isRunning = false
    private var generation = 0
    private var scanInProgress = false
    private var pendingScan: CodexDesktopTaskScan?

    init(
        sessionsRootURL: URL,
        discoverTranscripts: @escaping Discovery = CodexDesktopTaskMonitor.discoverRecursively,
        schedule: @escaping Schedule = CodexDesktopTaskMonitor.scheduleDefaultScan,
        onEvents: @escaping ([DesktopCodexTaskLifecycleEvent]) -> Void,
        onDiagnostic: @escaping (CodexDesktopTaskMonitorDiagnostic) -> Void = { _ in },
        onRead: @escaping ReadObserver = { _, _ in }
    ) {
        let root = sessionsRootURL.standardizedFileURL
        self.sessionsRootURL = root
        worker = CodexDesktopTaskMonitorWorker(
            sessionsRootURL: root,
            discoverTranscripts: discoverTranscripts,
            onRead: onRead
        )
        self.schedule = schedule
        self.onEvents = onEvents
        self.onDiagnostic = onDiagnostic
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        let activeGeneration = generation
        scanInProgress = true
        worker.start(deliver: delivery(for: activeGeneration))
        scheduledScan = schedule(sessionsRootURL) { [weak self] scan in
            guard self?.generation == activeGeneration else { return }
            self?.requestScan(scan)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        scheduledScan?.cancel()
        scheduledScan = nil
        activePollingTimer?.cancel()
        activePollingTimer = nil
        activeDesktopTaskIDs.removeAll()
        scanInProgress = false
        pendingScan = nil
        worker.reset()
    }

    func scanActiveTranscripts() {
        guard !activeDesktopTaskIDs.isEmpty else { return }
        requestScan(.paths([], includeActive: true))
    }

    func waitUntilIdleForTesting() async {
        repeat {
            await worker.waitUntilIdle()
        } while scanInProgress
    }

    private func requestScan(_ scan: CodexDesktopTaskScan) {
        guard isRunning else { return }
        if scanInProgress {
            pendingScan = pendingScan?.merging(scan) ?? scan
            return
        }
        scanInProgress = true
        worker.requestScan(scan, deliver: delivery(for: generation))
    }

    private func delivery(for activeGeneration: Int) -> @Sendable ([CodexDesktopTaskMonitorWorker.Output]) -> Void {
        { [weak self] outputs in
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.generation == activeGeneration else { return }
                for output in outputs {
                    guard self.generation == activeGeneration else { return }
                    switch output {
                    case let .events(events):
                        let reconciledEvents = self.updateActiveDesktopTasks(with: events)
                        self.onEvents(reconciledEvents)
                    case let .diagnostic(diagnostic): self.onDiagnostic(diagnostic)
                    }
                }
                guard self.generation == activeGeneration else { return }
                self.scanInProgress = false
                if let pendingScan = self.pendingScan {
                    self.pendingScan = nil
                    self.requestScan(pendingScan)
                }
            }
        }
    }

    /// Codex Desktop writes turns sequentially into a root transcript, but an
    /// interrupted turn may not get a terminal `task_complete`/`turn_aborted`
    /// record. When a later turn starts in that same transcript, retire any
    /// older active turns before publishing the new start. This prevents an
    /// orphaned turn from keeping the shared phone status stuck on running.
    private func updateActiveDesktopTasks(with events: [DesktopCodexTaskLifecycleEvent]) -> [DesktopCodexTaskLifecycleEvent] {
        var reconciledEvents: [DesktopCodexTaskLifecycleEvent] = []
        let activeTasksBeforeBatch = activeDesktopTaskIDs
        for event in events {
            switch event {
            case let .started(taskID):
                let supersededTaskIDs = activeTasksBeforeBatch
                    .filter { $0.transcriptID == taskID.transcriptID && $0.turnID != taskID.turnID }
                    .sorted { ($0.transcriptID, $0.turnID) < ($1.transcriptID, $1.turnID) }
                for supersededTaskID in supersededTaskIDs {
                    activeDesktopTaskIDs.remove(supersededTaskID)
                    reconciledEvents.append(.completed(supersededTaskID))
                }
                activeDesktopTaskIDs.insert(taskID)
                reconciledEvents.append(event)
            case let .completed(taskID):
                activeDesktopTaskIDs.remove(taskID)
                reconciledEvents.append(event)
            }
        }

        if activeDesktopTaskIDs.isEmpty {
            activePollingTimer?.cancel()
            activePollingTimer = nil
        } else if activePollingTimer == nil {
            activePollingTimer = CodexDesktopTaskMonitorPollingTimer(interval: 0.2) { [weak self] in
                self?.scanActiveTranscripts()
            }
        }
        return reconciledEvents
    }

    nonisolated private static func discoverRecursively(in root: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, error in
                traversalError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadNoPermission)
        }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { urls.append(url) }
        }
        if let traversalError { throw traversalError }
        return urls
    }

    @MainActor
    private static func scheduleDefaultScan(
        watching rootURL: URL,
        _ tick: @escaping @MainActor @Sendable (CodexDesktopTaskScan) -> Void
    ) -> CodexDesktopTaskMonitorCancellation {
        let watcher = CodexDesktopTaskMonitorFSEventWatcher(rootURL: rootURL, tick: tick)
        let pollingTimer = CodexDesktopTaskMonitorPollingTimer(interval: watcher == nil ? 1 : 15) { tick(.all) }
        return CodexDesktopTaskMonitorCancellation {
            watcher?.cancel()
            pollingTimer.cancel()
        }
    }
}
