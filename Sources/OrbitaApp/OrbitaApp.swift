import SwiftUI
import Sparkle
import OrbitaCore

@main
struct OrbitaApp: App {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: SparkleConfiguration.isReady,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup("Orbita") {
            ContentView()
                .frame(minWidth: 1180, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(
                    updater: updaterController.updater,
                    isConfigured: SparkleConfiguration.isReady
                )
            }
        }
    }
}

private enum SparkleConfiguration {
    static var isReady: Bool {
        guard let feedURL = bundleString("SUFeedURL"),
              URL(string: feedURL)?.scheme == "https",
              let publicKey = bundleString("SUPublicEDKey"),
              !publicKey.contains("$(") else {
            return false
        }
        return true
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    private let updater: SPUUpdater
    private let isConfigured: Bool

    init(updater: SPUUpdater, isConfigured: Bool) {
        self.updater = updater
        self.isConfigured = isConfigured
    }

    var body: some View {
        Button(L("app.menu.checkForUpdates"), action: updater.checkForUpdates)
            .disabled(!isConfigured)
    }
}
