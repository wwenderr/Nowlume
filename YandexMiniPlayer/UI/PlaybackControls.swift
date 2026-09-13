import SwiftUI

struct PlaybackControls: View {
    let isPlaying: Bool
    let onPrevious: () -> Void
    let onToggle: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            ControlButton(symbol: "backward.fill", size: 9, action: onPrevious)
                .accessibilityLabel("Previous track")
            ControlButton(symbol: isPlaying ? "pause.fill" : "play.fill", size: 11, prominent: true, action: onToggle)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
            ControlButton(symbol: "forward.fill", size: 9, action: onNext)
                .accessibilityLabel("Next track")
        }
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.88))
                .frame(width: prominent ? 27 : 22, height: prominent ? 27 : 22)
                .background {
                    Circle().fill(.white.opacity(prominent ? (hovering ? 0.25 : 0.18) : (hovering ? 0.12 : 0)))
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.16), value: hovering)
    }
}

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.89 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
