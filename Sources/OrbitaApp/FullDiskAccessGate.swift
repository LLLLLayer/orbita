import AppKit
import SwiftUI

enum FullDiskAccessStatus: Equatable {
    case unknown
    case granted
    case denied(String)

    var isGranted: Bool {
        if case .granted = self {
            return true
        }
        return false
    }
}

@MainActor
final class FullDiskAccessGate: ObservableObject {
    @Published private(set) var status: FullDiskAccessStatus = .unknown

    func refresh() {
        status = Self.currentStatus()
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private static func currentStatus() -> FullDiskAccessStatus {
        let probes = protectedProbeURLs()
        var existingProbeCount = 0

        for url in probes {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            guard !isDirectory.boolValue else {
                continue
            }
            existingProbeCount += 1

            do {
                let handle = try FileHandle(forReadingFrom: url)
                try handle.close()
                return .granted
            } catch {
                continue
            }
        }

        if existingProbeCount == 0 {
            return .denied("Orbita could not verify access to protected macOS folders. If you just enabled Full Disk Access, quit and reopen Orbita.")
        }

        return .denied("Orbita cannot verify Full Disk Access yet. Grant Full Disk Access, then quit and reopen Orbita.")
    }

    private static func protectedProbeURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        ]
    }
}

struct FullDiskAccessOnboardingView: View {
    let status: FullDiskAccessStatus
    let onOpenSettings: () -> Void
    let onContinueWithoutAccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 52)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 34, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 52, height: 52)
                        .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Orbita needs Full Disk Access")
                            .font(.title2.weight(.semibold))
                        Text("Orbita reads local coding-agent directories such as ~/.agents, ~/.codex, ~/.claude, project workspaces, package caches, and lock files. Enable Full Disk Access before using the app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("You can skip Full Disk Access and grant access to your home folder instead. Orbita will ask for that folder only after you choose to skip.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    PermissionStep(number: 1, title: "Open Privacy & Security", detail: "Click the button below to open System Settings.")
                    PermissionStep(number: 2, title: "Enable Orbita", detail: "Go to Full Disk Access and turn Orbita on. If Orbita is not listed, add the app manually.")
                    PermissionStep(number: 3, title: "Quit and reopen Orbita", detail: "macOS applies this permission to the next app launch.")
                }

                if case let .denied(message) = status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OrbitaTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 10) {
                    Button(action: onOpenSettings) {
                        Label("Open System Settings", systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: onContinueWithoutAccess) {
                        Label("Skip and Choose Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit Orbita", systemImage: "power")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(28)
            .frame(width: 620, alignment: .leading)
            .orbitaCard(cornerRadius: 22, shadowRadius: 14, shadowY: 8)

            Spacer(minLength: 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OrbitaTheme.canvas)
    }
}

private struct PermissionStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(OrbitaTheme.controlFill, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
