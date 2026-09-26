import SwiftUI

struct CompactNotchView: View {
    @EnvironmentObject private var viewModel: PlayerViewModel
    var showsTitle = true

    var body: some View {
        HStack(spacing: 6) {
            artwork

            if showsTitle {
                Text(viewModel.track?.title ?? "Nowlume")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            MiniEqualizer(isPlaying: viewModel.track?.isPlaying == true)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.97))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.7))
        .padding(1)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = viewModel.track?.artwork {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

private struct MiniEqualizer: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 5.0
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(isPlaying ? 0.86 : 0.40))
                        .frame(
                            width: 2,
                            height: isPlaying
                                ? 4 + abs(sin(phase + Double(index) * 1.7)) * 7
                                : 4
                        )
                }
            }
            .frame(width: 9, height: 12)
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var viewModel: PlayerViewModel
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        ZStack {
            AnimatedBackground(
                palette: viewModel.palette,
                artwork: viewModel.track?.artwork,
                isPlaying: viewModel.track?.isPlaying == true,
                isVisible: viewModel.isPlayerVisible,
                reduceAnimations: preferences.reduceAnimations
            )

            if let track = viewModel.track {
                playingContent(track)
                    .transition(.opacity)
            } else {
                idleContent
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.8))
        .padding(1)
    }

    private func playingContent(_ track: Track) -> some View {
        HStack(spacing: 11) {
            ArtworkView(
                artwork: track.artwork,
                transitionID: viewModel.transitionID,
                isPlaying: track.isPlaying,
                reduceAnimations: preferences.reduceAnimations
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.67))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    PlaybackControls(
                        isPlaying: track.isPlaying,
                        onPrevious: viewModel.previous,
                        onToggle: viewModel.togglePlayPause,
                        onNext: viewModel.next
                    )
                    .fixedSize()
                }
                .id(viewModel.transitionID)
                .transition(.opacity.combined(with: .offset(y: 4)))

                TimelineView(.animation(minimumInterval: 0.5, paused: !viewModel.isPlayerVisible || !track.isPlaying)) { context in
                    TrackProgressView(elapsed: viewModel.displayedElapsed(at: context.date), duration: track.duration)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 14)
    }

    private var idleContent: some View {
        HStack(spacing: 11) {
            ArtworkView(artwork: nil, transitionID: viewModel.transitionID, isPlaying: false, reduceAnimations: preferences.reduceAnimations)
            VStack(alignment: .leading, spacing: 5) {
                Text("Nothing playing")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Start playing from any music app")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.61))
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 14)
    }
}
