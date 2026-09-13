import AppKit
import SwiftUI

struct MenuBarContent: View {
    var body: some View {
        Button("Reveal Player") { PlayerWindowController.shared.reveal() }
            .keyboardShortcut("p")

        Toggle("Launch at Login", isOn: Binding(
            get: { LaunchAtLoginService.isEnabled },
            set: { newValue in try? LaunchAtLoginService.setEnabled(newValue) }
        ))

        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
