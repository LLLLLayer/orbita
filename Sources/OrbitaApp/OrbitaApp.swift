import SwiftUI
import Sparkle
import OrbitaCore

@main
struct OrbitaApp: App {
    private let updaterController: SPUStandardUpdaterController
    private let updateAvailability: UpdateAvailabilityController

    init() {
        let availability = UpdateAvailabilityController()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: SparkleConfiguration.isReady,
            updaterDelegate: SparkleConfiguration.isReady ? availability : nil,
            userDriverDelegate: nil
        )
        updateAvailability = availability
        if SparkleConfiguration.isReady {
            availability.start(updater: updaterController.updater)
        }
    }

    var body: some Scene {
        WindowGroup("Orbita") {
            ContentView(
                updateAvailability: updateAvailability,
                onCheckForUpdates: { updaterController.updater.checkForUpdates() },
                updatesConfigured: SparkleConfiguration.isReady
            )
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

/// Drives the unobtrusive "update available" badge in the collapsed sidebar. It runs Sparkle's SILENT
/// probe (`checkForUpdateInformation`, no UI) on a slow cadence; when the appcast offers a newer build
/// the delegate flips `updateAvailable`, and the badge — when clicked — opens Sparkle's standard install
/// flow. Only active when Sparkle is configured (a real signed feed); dev builds never show the badge.
@MainActor
final class UpdateAvailabilityController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var updateAvailable = false

    private weak var updater: SPUUpdater?
    private var probeTimer: Timer?

    /// Probe the appcast roughly every six hours, plus once shortly after launch. The badge is the only
    /// surfaced signal — no automatic popup — so a slow cadence is plenty.
    private let probeInterval: TimeInterval = 6 * 60 * 60

    func start(updater: SPUUpdater) {
        self.updater = updater
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            self.probe()
        }
        let timer = Timer(timeInterval: probeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probe() }
        }
        RunLoop.main.add(timer, forMode: .common)
        probeTimer = timer
    }

    private func probe() {
        updater?.checkForUpdateInformation()
    }

    // MARK: - SPUUpdaterDelegate
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.updateAvailable = true
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.updateAvailable = false
        }
    }
}
