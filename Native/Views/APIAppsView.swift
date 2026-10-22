import SwiftUI

struct APIAppsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private enum Layout: String, CaseIterable {
        case list, grid, compact

        var title: String {
            switch self {
            case .list: "리스트"
            case .grid: "그리드"
            case .compact: "간단한 목록"
            }
        }

        var icon: String {
            switch self {
            case .list: "list.bullet"
            case .grid: "square.grid.2x2"
            case .compact: "line.3.horizontal"
            }
        }
    }

    let store: LaunchpadStore
    @Binding var selection: MainScreen
    let onOpenSettings: () -> Void
    @State private var apps: [RegisteredAppAPI] = []
    @State private var statuses: [String: AppAPIMCPBridge.ConnectionStatus] = [:]
    @State private var isDropTargeted = false
    @State private var dropError: String?
    @State private var lastDiscovery = Date.distantPast
    @AppStorage("linkdeck.api-apps-layout") private var layout: Layout = .list

    var body: some View {
        VStack(spacing: 0) {
            appContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                headerControls
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(colorScheme == .dark ? Color(white: 9 / 255) : MacAppearance(scheme: colorScheme).canvas)
        .contentShape(Rectangle())
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            registerDroppedApps(urls)
        } isTargeted: { isDropTargeted = $0 }
        .alert("API 앱을 추가하지 못했습니다.", isPresented: Binding(
            get: { dropError != nil }, set: { if !$0 { dropError = nil } }
        )) {
            Button("확인", role: .cancel) { dropError = nil }
        } message: {
            Text(dropError ?? "")
        }
        .task { await refreshApps() }
        .onChange(of: store.pages) { lastDiscovery = .distantPast }
        .onChange(of: store.smartphonePages) { lastDiscovery = .distantPast }
    }

    private var headerControls: some View {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Layout.allCases, id: \.self) { item in
                        Button { layout = item } label: {
                            Image(systemName: item.icon)
                                .font(.system(size: 12, weight: .regular))
                                .frame(width: 27.09, height: 20.2)
                                .background(layout == item ? Color(white: 80 / 255) : .clear,
                                            in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(layout == item ? .isSelected : [])
                        .help(item.title)
                    }
                }
                .foregroundStyle(Color(white: 210 / 255))
                .background(Color(white: 25 / 255), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 56 / 255), lineWidth: 0.5))
                HStack(spacing: 3) {
                    screenButton(.smartphoneButtons, title: "휴대폰", icon: "iphone")
                    screenButton(.apiApps, title: "API 앱", icon: "point.3.connected.trianglepath.dotted")
                }
                .padding(.leading, 6.5)
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 148 / 255))
                    .frame(width: 18, height: 24)
                    .padding(.leading, 23.8)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("설정")
            }
            .padding(.trailing, 6)
            .frame(height: 24)
    }

    private var appContent: some View {
            Group {
            if apps.isEmpty {
                Text("API 앱을 여기에 드래그하세요.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layout == .grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                        ForEach(apps) { app in
                            let status = statuses[app.id] ?? .idle
                            VStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                                    .resizable().frame(width: 36, height: 36)
                                Text(app.manifest.name)
                                    .font(.callout).lineLimit(1)
                                statusLabel(status, approved: app.approved)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                            .contextMenu { approvalMenu(for: app) }
                        }
                    }
                    .padding(12)
                }
            } else {
                ScrollView {
                LazyVStack(spacing: 0) {
                ForEach(apps) { app in
                    let status = statuses[app.id] ?? .idle
                    HStack(spacing: 11) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                            .resizable().frame(width: layout == .compact ? 16 : 28, height: layout == .compact ? 16 : 28)
                        Text(app.manifest.name)
                            .font(.custom("Helvetica", size: 14))
                            .foregroundStyle(colorScheme == .dark ? Color(white: 215 / 255) : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        statusLabel(status, approved: app.approved, compact: true)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: layout == .compact ? 28 : 44)
                    .overlay(alignment: .top) {
                        if app.id != apps.first?.id {
                            Rectangle().fill(colorScheme == .dark ? Color(white: 55 / 255) : Color.primary.opacity(0.15))
                                .frame(height: 1).padding(.leading, 20)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu { approvalMenu(for: app) }
                }
                }
                }
                .background(colorScheme == .dark ? Color(white: 31 / 255) : Color(nsColor: .controlBackgroundColor))
            }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
    }

    private func registerDroppedApps(_ urls: [URL]) -> Bool {
            var added = false
            var errors: [String] = []
            for url in urls {
                do {
                    let app = try RegisteredAppAPI.register(appURL: url)
                    apps.removeAll { $0.id == app.id }
                    apps.append(app)
                    added = true
                } catch {
                    errors.append(url.lastPathComponent + ": " + error.localizedDescription)
                }
            }
            apps.sort { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
            if !errors.isEmpty { dropError = errors.joined(separator: "\n") }
            return added
    }

    private func refreshApps() async {
            while !Task.isCancelled {
                if Date().timeIntervalSince(lastDiscovery) >= 30 {
                let buttons = LinkDeckMCPHandler.buttons(macPages: store.pages, phonePages: store.smartphonePages)
                let discovered = RegisteredAppAPI.discover(buttons: buttons)
                    .sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
                if apps != discovered { apps = discovered }
                lastDiscovery = Date()
                }
                var updated: [String: AppAPIMCPBridge.ConnectionStatus] = [:]
                for app in apps {
                    updated[app.id] = await SubtitlePipelineRuntime.shared.appAPIs.connectionStatus(for: app)
                }
                guard !Task.isCancelled else { return }
                if statuses != updated { statuses = updated }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
    }

    @ViewBuilder
    private func screenButton(_ screen: MainScreen, title: String, icon: String) -> some View {
        let selected = selection == screen
        Button { selection = screen } label: {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 21.13, height: 19.62)
                .foregroundStyle(selected ? Color.orange : Color(white: 180 / 255))
                .background(selected ? Color(red: 51 / 255, green: 33 / 255, blue: 17 / 255) : Color(white: 28 / 255),
                            in: RoundedRectangle(cornerRadius: 7.5))
                .overlay(RoundedRectangle(cornerRadius: 7.5).stroke(selected ? Color.orange : Color(white: 64 / 255), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
    }

    @ViewBuilder
    private func approvalMenu(for app: RegisteredAppAPI) -> some View {
        if !app.approved {
            Button("연결 허용") {
                app.approve()
                Task {
                    statuses[app.id] = await SubtitlePipelineRuntime.shared.appAPIs.connectionStatus(for: app)
                }
            }
        }
    }

    private func statusLabel(_ status: AppAPIMCPBridge.ConnectionStatus, approved: Bool, compact: Bool = false) -> some View {
        HStack(spacing: 4.5) {
            Circle().fill(approved ? Color(red: 39 / 255, green: 207 / 255, blue: 92 / 255) : .red).frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(compact ? .custom("AppleSDGothicNeo-Regular", size: 10) : .caption)
                .foregroundStyle(colorScheme == .dark ? Color(white: 155 / 255) : .secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(approved ? "연결 허용됨, \(status.rawValue)" : "연결 허용 필요")
    }
}

struct MainWindowModeSize: NSViewRepresentable {
    let compact: Bool

    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ view: WindowView, context: Context) {
        view.compact = compact
        DispatchQueue.main.async { view.applySize() }
    }

    final class WindowView: NSView {
        var compact = false
        var appliedCompact: Bool?
        var expandedFrame: NSRect?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { self.applySize() }
        }

        func applySize() {
            guard let window else { return }
            if compact, let toolbar = window.toolbar,
               toolbar.items.first?.itemIdentifier != .flexibleSpace {
                toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 0)
            }
            guard appliedCompact != compact else { return }
            if compact {
                expandedFrame = window.frame
                window.toolbarStyle = .unifiedCompact
                window.contentMinSize = NSSize(width: 360, height: 240)
                window.contentMaxSize = NSSize(width: 420, height: 400)
                window.setContentSize(NSSize(width: 420, height: 400))
            } else {
                window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                window.contentMinSize = NSSize(width: 1100, height: 640)
                if let expandedFrame { window.setFrame(expandedFrame, display: true) }
            }
            appliedCompact = compact
        }
    }
}
