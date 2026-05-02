import SwiftUI
import UIKit

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
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @AppStorage("hapticDevPanelEnabled") private var hapticDevPanelEnabled = false

    @State private var versionTapCount = 0
    @State private var versionTapResetTask: Task<Void, Never>?
    @State private var showUnlockToast = false

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
                    .contentShape(Rectangle())
                    .onTapGesture { handleVersionTap() }
                LabeledContent("Developer", value: "Ravindu Lachitha")
            }

            if developerModeEnabled {
                Section {
                    Toggle("Live Haptic Panel", isOn: $hapticDevPanelEnabled)
                    Button(role: .destructive) {
                        developerModeEnabled = false
                        hapticDevPanelEnabled = false
                    } label: {
                        Text("Disable Developer Mode")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Overlays a live haptic heatmap and event ticker on the player when haptics are present.")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if showUnlockToast {
                Text("Developer mode enabled")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.78), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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

    private func handleVersionTap() {
        if developerModeEnabled { return }

        versionTapCount += 1
        versionTapResetTask?.cancel()

        if versionTapCount >= 7 {
            versionTapCount = 0
            developerModeEnabled = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showUnlockToast = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showUnlockToast = false
                    }
                }
            }
        } else {
            versionTapResetTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await MainActor.run { versionTapCount = 0 }
            }
        }
    }
}
