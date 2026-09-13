import SwiftUI

struct TrackProgressView: View {
    let elapsed: TimeInterval
    let duration: TimeInterval

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(Self.formatted(elapsed))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 3)
                    Capsule().fill(.white.opacity(0.82)).frame(width: max(3, proxy.size.width * fraction), height: 3)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8)
            Text(Self.formatted(duration))
        }
        .font(.system(size: 7.5, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.62))
    }

    private static func formatted(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let seconds = Int(interval.rounded(.down))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
