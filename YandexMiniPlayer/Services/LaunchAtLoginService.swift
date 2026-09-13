import OSLog
import ServiceManagement

enum LaunchAtLoginService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "YandexMiniPlayer", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
        logger.info("Launch at login is now \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
