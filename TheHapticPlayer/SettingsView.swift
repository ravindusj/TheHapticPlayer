import SwiftUI

enum AppTheme: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var appTheme: Int = AppTheme.system.rawValue
    @AppStorage("autoResume") private var autoResume = false
    @AppStorage("defaultPlaybackSpeed") private var defaultPlaybackSpeed: Double = 1.0

    private let speedOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Auto Resume", isOn: $autoResume)
                Picker("Default Speed", selection: $defaultPlaybackSpeed) {
                    ForEach(speedOptions, id: \.self) { speed in
                        Text(speedLabel(speed)).tag(speed)
                    }
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Auto Resume skips the resume prompt and continues from where you left off.")
            }

            Section("About") {
                LabeledContent("App", value: "TheHaptic Player")
                LabeledContent("Version", value: appVersion)
                LabeledContent("Developer", value: "Ravindu Lachitha")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func speedLabel(_ speed: Double) -> String {
        if speed == 1.0 { return "1x (Normal)" }
        if speed.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(speed))x"
        }
        return "\(speed)x"
    }
}
