import Foundation
import OSLog
import SwiftUI

@MainActor
final class PlayerViewModel: ObservableObject {
    static let shared = PlayerViewModel(provider: MediaRemoteProvider())

    @Published var isPlayerVisible = false
    @Published private(set) var track: Track?
    @Published private(set) var palette = DominantColorService.fallback
    @Published private(set) var transitionID = UUID()

    private let provider: NowPlayingProvider
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YandexMiniPlayer", category: "Player")
    private var pollingTask: Task<Void, Never>?
    private var trackReceivedAt = Date()
    private var consecutiveEmptyResults = 0

    init(provider: NowPlayingProvider) {
        self.provider = provider
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.track?.isPlaying == true ? 1.2 : 0.6
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refresh() async {
        let latest = await provider.getCurrentTrack()
        guard let latest else {
            consecutiveEmptyResults += 1
            if consecutiveEmptyResults >= 2 { track = nil }
            return
        }
        consecutiveEmptyResults = 0

        let changed = latest.identifier != track?.identifier
            || latest.title != track?.title
            || latest.artist != track?.artist
        let receivedAt = Date()

        if changed {
            // MediaRemote keeps paused browser tabs in its session carousel.
            // Never replace the visible item with a different, inactive session;
            // keep the last real player until another item is actually playing.
            guard latest.isPlaying else { return }

            trackReceivedAt = receivedAt
            transitionID = UUID()
            withAnimation(.easeInOut(duration: Preferences.shared.reduceAnimations ? 0.01 : 0.38)) {
                track = latest
            }
            let colors = await DominantColorService.shared.colors(for: latest.artworkData)
            withAnimation(.easeInOut(duration: Preferences.shared.reduceAnimations ? 0.01 : 1.15)) {
                palette = colors
            }
        } else {
            let previousElapsed = track?.elapsedTime ?? 0
            let estimatedBeforeRefresh = displayedElapsed(at: receivedAt)
            let providerAdvanced = latest.elapsedTime > previousElapsed + 0.2
            let reconciledElapsed = latest.isPlaying && track?.isPlaying == true && !providerAdvanced
                ? estimatedBeforeRefresh
                : latest.elapsedTime

            track = Track(
                identifier: latest.identifier,
                title: latest.title,
                artist: latest.artist,
                album: latest.album,
                artwork: latest.artwork,
                artworkData: latest.artworkData,
                duration: latest.duration,
                elapsedTime: reconciledElapsed,
                isPlaying: latest.isPlaying
            )
            trackReceivedAt = receivedAt
        }
    }

    func displayedElapsed(at date: Date = Date()) -> TimeInterval {
        guard let track else { return 0 }
        let extrapolated = track.elapsedTime + (track.isPlaying ? date.timeIntervalSince(trackReceivedAt) : 0)
        return min(max(0, extrapolated), max(track.duration, 0))
    }

    func togglePlayPause() {
        let previousValue = track
        if let current = track {
            track = Track(
                identifier: current.identifier, title: current.title, artist: current.artist,
                album: current.album, artwork: current.artwork, artworkData: current.artworkData,
                duration: current.duration, elapsedTime: displayedElapsed(), isPlaying: !current.isPlaying
            )
            trackReceivedAt = Date()
        }
        Task {
            await provider.togglePlayPause()
            try? await Task.sleep(for: .milliseconds(220))
            await refresh()
            if track == nil { track = previousValue }
        }
    }

    func next() {
        Task { await provider.next(); try? await Task.sleep(for: .milliseconds(250)); await refresh() }
    }

    func previous() {
        Task { await provider.previous(); try? await Task.sleep(for: .milliseconds(250)); await refresh() }
    }
}
