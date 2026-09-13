import Foundation
import OSLog

final class MediaRemoteHelperClient: @unchecked Sendable {
    static let shared = MediaRemoteHelperClient()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YandexMiniPlayer", category: "MediaRemoteHelper")

    func getNowPlayingInfo() async -> [String: Any]? {
        await Task.detached(priority: .userInitiated) { [self] in
            run(symbol: "YMPReadNowPlaying")
        }.value
    }

    func send(command: Int) async -> Bool {
        await Task.detached(priority: .userInitiated) { [self] in
            run(symbol: "YMPPerformCommand", environment: ["YMP_COMMAND": String(command)])?["success"] as? Bool ?? false
        }.value
    }

    private func run(symbol: String, environment: [String: String] = [:]) -> [String: Any]? {
        guard let scriptURL = Bundle.main.url(forResource: "YMPMediaRemote", withExtension: "pl"),
              let libraryURL = helperLibraryURL() else {
            logger.error("Bundled MediaRemote helper resources are missing")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, libraryURL.path, symbol]
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  !object.isEmpty else { return nil }

            var result = object
            if let base64 = object["artworkData"] as? String {
                result["artworkData"] = Data(base64Encoded: base64)
            }
            return result
        } catch {
            logger.error("MediaRemote helper failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func helperLibraryURL() -> URL? {
        let candidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libMediaRemoteHelper.dylib"),
            Bundle.main.resourceURL?.appendingPathComponent("libMediaRemoteHelper.dylib")
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
