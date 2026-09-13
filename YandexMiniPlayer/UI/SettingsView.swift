import SwiftUI

struct SettingsView: View {
    @ObservedObject private var preferences = Preferences.shared
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    do {
                        try LaunchAtLoginService.setEnabled(value)
                        loginError = nil
                    } catch {
                        loginError = "Couldn’t update Login Items. Try again in System Settings."
                        launchAtLogin = LaunchAtLoginService.isEnabled
                    }
                }
            Toggle("Reduce animations", isOn: $preferences.reduceAnimations)

            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 390, height: 170)
        .navigationTitle("Nowlume")
    }
}
