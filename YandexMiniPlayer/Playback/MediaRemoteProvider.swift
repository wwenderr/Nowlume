import AppKit
import Foundation
import OSLog

final class MediaRemoteProvider: NowPlayingProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YandexMiniPlayer", category: "MediaRemote")

    // Reuse the decoded image while polling the same artwork.
    private var cachedArtworkData: Data?
    private var cachedArtwork: NSImage?
    private let artworkLock = NSLock()

    private func artwork(for data: Data?) -> NSImage? {
        artworkLock.lock()
        defer { artworkLock.unlock() }
        if data != cachedArtworkData {
            cachedArtworkData = data
            cachedArtwork = data.flatMap(NSImage.init(data:))
        }
        return cachedArtwork
    }

    func getCurrentTrack() async -> Track? {
        let info: [String: Any]?
        if #available(macOS 15.4, *) {
            info = await MediaRemoteHelperClient.shared.getNowPlayingInfo()
        } else {
            guard MediaRemoteBridge.isAvailable() else {
                logger.error("MediaRemote is unavailable")
                return nil
            }

            info = await withCheckedContinuation { continuation in
                MediaRemoteBridge.getNowPlayingInfo { rawInfo in
                    continuation.resume(returning: rawInfo as? [String: Any])
                }
            }
        }

        guard let info,
              let title = info["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let artist = (info["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = info["album"] as? String
        let duration = Self.number(info["duration"])
        let elapsed = Self.number(info["elapsedTime"])
        let rate = Self.number(info["playbackRate"])
        let artworkData = info["artworkData"] as? Data
        let artwork = artwork(for: artworkData)
        let identifier = (info["identifier"] as? String) ?? "\(title)|\(artist ?? "")|\(album ?? "")"

        return Track(
            identifier: identifier,
            title: title,
            artist: artist?.isEmpty == false ? artist! : "Unknown Artist",
            album: album,
            artwork: artwork,
            artworkData: artworkData,
            duration: max(0, duration),
            elapsedTime: max(0, elapsed),
            isPlaying: rate > 0.01
        )
    }

    func togglePlayPause() async { await send(command: 2, name: "toggle play/pause") }
    func next() async { await send(command: 4, name: "next") }
    func previous() async { await send(command: 5, name: "previous") }

    private func send(command: Int, name: String) async {
        let succeeded: Bool
        if #available(macOS 15.4, *) {
            succeeded = await MediaRemoteHelperClient.shared.send(command: command)
        } else {
            succeeded = MediaRemoteBridge.sendCommand(command)
        }
        guard succeeded else {
            logger.error("MediaRemote command failed: \(name, privacy: .public)")
            return
        }
    }

    private static func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        return 0
    }
}
