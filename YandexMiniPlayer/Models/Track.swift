import AppKit
import Foundation

struct Track {
    let identifier: String
    let title: String
    let artist: String
    let album: String?
    let artwork: NSImage?
    let artworkData: Data?
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let isPlaying: Bool
}
