import Combine
import SwiftUI

struct AnimatedBackground: View {
    let palette: [PaletteColor]
    let artwork: NSImage?
    let isPlaying: Bool
    let reduceAnimations: Bool
    @State private var animationDate = Date()

    private let animationTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    private var colors: [Color] {
        let source = palette.isEmpty ? DominantColorService.fallback : palette
        let shifts = [0.0, 0.08, -0.06, 0.48, 0.56]
        return source.enumerated().map { index, value in
            value.vividColor(hueShift: shifts[index % shifts.count])
        }
    }

    var body: some View {
        ZStack {
            VisualEffectView()

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 40)
                    .opacity(0.18)
                    .scaleEffect(1.35)
            }

            GeometryReader { proxy in
                    let cycle = animationDate.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 8.0) / 8.0
                    let phase = cycle * 2.0 * Double.pi
                    ZStack {
                        LinearGradient(
                            colors: [color(0), color(3), color(1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                        AngularGradient(
                            colors: [color(0).opacity(0.82), color(1), color(2), color(4), color(0).opacity(0.82)],
                            center: .center
                        )
                        .frame(width: proxy.size.width * 1.45, height: proxy.size.width * 1.45)
                        .rotationEffect(.degrees(cycle * 360.0))
                        .position(x: proxy.size.width * 0.58, y: proxy.size.height * 0.48)
                        .blur(radius: 12)

                        blob(color: color(0), width: proxy.size.width * 0.72, height: proxy.size.height * 1.7,
                             x: proxy.size.width * (0.10 + 0.16 * sin(phase)),
                             y: proxy.size.height * (0.18 + 0.21 * cos(phase)))
                        blob(color: color(1), width: proxy.size.width * 0.62, height: proxy.size.height * 1.9,
                             x: proxy.size.width * (0.76 + 0.13 * cos(phase)),
                             y: proxy.size.height * (0.62 + 0.18 * sin(phase)))
                        blob(color: color(2), width: proxy.size.width * 0.46, height: proxy.size.height * 1.55,
                             x: proxy.size.width * (0.44 + 0.18 * sin(phase + 2.1)),
                             y: proxy.size.height * (0.38 + 0.22 * cos(phase + 1.2)))
                        blob(color: color(3), width: proxy.size.width * 0.40, height: proxy.size.height * 1.35,
                             x: proxy.size.width * (0.28 + 0.12 * cos(phase * 2.0 + 0.8)),
                             y: proxy.size.height * (0.70 + 0.14 * sin(phase + 0.4)))
                        blob(color: color(4), width: proxy.size.width * 0.30, height: proxy.size.height * 1.15,
                             x: proxy.size.width * (0.62 + 0.20 * sin(phase + 3.4)),
                             y: proxy.size.height * (0.18 + 0.16 * cos(phase * 2.0)))

                        RoundedRectangle(cornerRadius: 100, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.27), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 1.8)
                            .rotationEffect(.degrees(-18))
                            .offset(x: proxy.size.width * 0.62 * sin(phase))
                            .blur(radius: 20)
                    }
                    .hueRotation(.degrees(sin(phase) * 4))
                    .saturation(1.25)
                    .contrast(1.08)
            }
            .opacity(0.96)
            .onReceive(animationTimer) { date in
                animationDate = date
            }

            LinearGradient(
                colors: [Color.black.opacity(0.03), Color.black.opacity(0.27)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.black.opacity(0.05)
        }
        .clipped()
    }

    private func color(_ index: Int) -> Color {
        colors[index % colors.count]
    }

    private func blob(color: Color, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [color.opacity(0.96), color.opacity(0)], center: .center, startRadius: 0, endRadius: max(width, height) / 2))
            .frame(width: width, height: height)
            .position(x: x, y: y)
            .blur(radius: 18)
    }
}
