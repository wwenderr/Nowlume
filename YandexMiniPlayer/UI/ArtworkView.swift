import SwiftUI

struct ArtworkView: View {
    let artwork: NSImage?
    let transitionID: UUID
    let isPlaying: Bool
    let reduceAnimations: Bool
    @State private var isHovering = false

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .id(transitionID)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.34), radius: 8, y: 3)
        .scaleEffect(isHovering ? 1.025 : (isPlaying && !reduceAnimations ? 1.01 : 1))
        .animation(reduceAnimations ? nil : .easeInOut(duration: 0.22), value: isHovering)
        .animation(reduceAnimations ? nil : .easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: isPlaying)
        .onHover { isHovering = $0 }
    }
}
