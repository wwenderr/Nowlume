import Foundation

protocol NowPlayingProvider: AnyObject {
    func getCurrentTrack() async -> Track?
    func togglePlayPause() async
    func next() async
    func previous() async
}
