import SwiftUI

struct PadButton: View {
    let pad: Pad
    let selected: Bool
    var circular = false
    var executeOnPress = false
    var displayColor: String?
    let action: () -> Void
    var runAction: (() -> Void)? = nil

    @State private var pressed = false

    var body: some View {
        Button {
            pressed = true
            action()
            if executeOnPress { runAction?() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { pressed = false }
        } label: {
            VStack(spacing: 1) {
                if !pad.activeTitle.isEmpty || !pad.activeSymbol.isEmpty {
                    Image(systemName: pad.activeSymbol)
                        .font(.system(size: circular ? 15 : 14, weight: .medium))
                }
                if !pad.activeTitle.isEmpty {
                    Text(pad.activeTitle)
                        .font(.system(size: circular ? 8 : 9, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(3)
            .background {
                if circular {
                    Circle().fill(padColor)
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(padColor)
                }
            }
            .overlay {
                if circular {
                    Circle().stroke(selected ? Color.orange : .white.opacity(0.18), lineWidth: selected ? 2 : 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.orange : .white.opacity(0.18), lineWidth: selected ? 2 : 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if pad.secondAction != nil {
                    Text(pad.isSecondActionActive ? "B" : "A")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: selected ? .orange.opacity(0.8) : (pad.stateColor == "off" ? .clear : padColor.opacity(0.62)), radius: selected ? 11 : 8)
            .scaleEffect(pressed ? 0.96 : (selected ? 1.035 : 1))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .contextMenu {
            if let runAction {
                Button("동작 실행", action: runAction)
            }
        }
    }

    private var padColor: Color {
        PadColor(rawValue: pressed ? pad.activeColor : (displayColor ?? pad.stateColor))?.color ?? .gray
    }
}
