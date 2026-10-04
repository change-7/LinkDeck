import SwiftUI

enum MainScreen: Hashable {
    case launchpadMini
    case smartphoneButtons
}

struct MainScreenSidebarNavigation: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Binding var selection: MainScreen
    let midiIsConnected: Bool
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 4) {
                    screenButton(.smartphoneButtons, title: "휴대폰", systemImage: "iphone")
                    screenButton(.launchpadMini, title: "런치패드 미니", systemImage: "square.grid.3x3")
                }
            } else {
                VStack(spacing: 4) {
                    screenButton(.smartphoneButtons, title: "휴대폰", systemImage: "iphone")
                    screenButton(.launchpadMini, title: "런치패드 미니", systemImage: "square.grid.3x3")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("화면 모드 선택")
    }

    private func screenButton(_ screen: MainScreen, title: String, systemImage: String) -> some View {
        let isSelected = selection == screen
        let isAvailable = screen != .launchpadMini || midiIsConnected
        return Button {
            guard isAvailable else { return }
            selection = screen
        } label: {
            Group {
                if compact {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 26)
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .padding(.horizontal, 8)
                }
            }
            .foregroundStyle(isSelected ? theme.accent : MacAppearance(scheme: colorScheme).foreground.opacity(0.72))
            .background(
                isSelected ? theme.accent.opacity(0.18) : MacAppearance(scheme: colorScheme).control,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? theme.accent.opacity(0.9) : MacAppearance(scheme: colorScheme).border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.38)
        .focusable(false)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityHint(isAvailable ? "" : "Launchpad Mini를 연결하면 사용할 수 있습니다.")
        .help(isAvailable ? title : "Launchpad Mini를 연결하면 사용할 수 있습니다.")
    }
}

struct MainSidebarFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    let codexIsConnected: Bool
    let midiIsConnected: Bool
    let onOpenBackupRestore: () -> Void
    let onOpenCodexSettings: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(codexIsConnected ? .green : .gray)
                .frame(width: 7, height: 7)
            Circle()
                .fill(midiIsConnected ? .green : .gray)
                .frame(width: 7, height: 7)
            Spacer(minLength: 0)
            Button(action: onOpenBackupRestore) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 29, height: 28)
                    .background(MacAppearance(scheme: colorScheme).control, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(MacAppearance(scheme: colorScheme).border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정·버튼 백업 및 복구")
            .help("Mac 버튼, 스마트폰 버튼, Codex 모션 설정을 백업하거나 복구합니다.")

            Button(action: onOpenCodexSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 29, height: 28)
                    .background(MacAppearance(scheme: colorScheme).control, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(MacAppearance(scheme: colorScheme).border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("설정")
            .help("Mac 화면 모드, Codex 연결과 알림을 설정합니다.")
        }
        .foregroundStyle(MacAppearance(scheme: colorScheme).foreground)
        .padding(.top, 7)
        .overlay(alignment: .top) {
            Divider().overlay(MacAppearance(scheme: colorScheme).border)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("연결 상태와 설정")
        .accessibilityValue("Codex \(codexIsConnected ? "연결됨" : "연결 안 됨"), Launchpad Mini \(midiIsConnected ? "연결됨" : "연결 안 됨")")
    }
}
