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
    let directoryAccessMessage: String?
    let isPreflightingDirectoryAccess: Bool
    let onOpenSettings: () -> Void
    let onContinueWithoutAccess: () -> Void

    var body: some View {
        ZStack {
            FloatingIconBackdrop()
                .allowsHitTesting(false)

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
                        Text("If you skip, Orbita will preflight the exact user and project paths it is about to scan so macOS can show permission prompts before the workspace opens.")
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

                if let directoryAccessMessage, !isPreflightingDirectoryAccess {
                    Label(directoryAccessMessage, systemImage: "folder.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OrbitaTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Button(action: onOpenSettings) {
                        Label("Open System Settings", systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: onContinueWithoutAccess) {
                        Label(isPreflightingDirectoryAccess ? "Checking Access" : "Skip and Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isPreflightingDirectoryAccess)

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

private struct FloatingIconBackdrop: View {
    private static let icons: [String] = [
        "shippingbox",
        "wand.and.stars",
        "person.2",
        "terminal",
        "server.rack",
        "link",
        "square.grid.2x2"
    ]

    private let particles: [Particle]

    init() {
        particles = Self.makeParticles()
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(particles) { particle in
                        Image(systemName: particle.symbol)
                            .font(.system(size: particle.size, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(particle.opacity))
                            .rotationEffect(.degrees(particle.rotation(at: t)))
                            .position(particle.position(at: t, in: proxy.size))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private struct Particle: Identifiable {
        let id = UUID()
        let symbol: String
        let size: CGFloat
        let opacity: Double
        let originX: CGFloat
        let originY: CGFloat
        let amplitudeX: CGFloat
        let amplitudeY: CGFloat
        let speedX: Double
        let speedY: Double
        let phaseX: Double
        let phaseY: Double
        let rotationSpeed: Double
        let rotationPhase: Double

        func position(at time: TimeInterval, in size: CGSize) -> CGPoint {
            let x = originX * size.width + amplitudeX * CGFloat(sin(time * speedX + phaseX))
            let y = originY * size.height + amplitudeY * CGFloat(cos(time * speedY + phaseY))
            return CGPoint(x: x, y: y)
        }

        func rotation(at time: TimeInterval) -> Double {
            (time * rotationSpeed + rotationPhase).truncatingRemainder(dividingBy: 360)
        }
    }

    private static func makeParticles() -> [Particle] {
        var generator = SeededGenerator(seed: 0x0BB17A11)
        let count = 14
        return (0..<count).map { index in
            let symbol = icons[index % icons.count]
            let size = CGFloat.random(in: 36...86, using: &generator)
            let opacity = Double.random(in: 0.05...0.11, using: &generator)
            let originX = CGFloat.random(in: 0.05...0.95, using: &generator)
            let originY = CGFloat.random(in: 0.05...0.95, using: &generator)
            let amplitudeX = CGFloat.random(in: 32...90, using: &generator)
            let amplitudeY = CGFloat.random(in: 32...90, using: &generator)
            let speedX = Double.random(in: 0.10...0.30, using: &generator)
            let speedY = Double.random(in: 0.10...0.30, using: &generator)
            let phaseX = Double.random(in: 0...(2 * .pi), using: &generator)
            let phaseY = Double.random(in: 0...(2 * .pi), using: &generator)
            let rotationSpeed = Double.random(in: -14...14, using: &generator)
            let rotationPhase = Double.random(in: 0...360, using: &generator)
            return Particle(
                symbol: symbol,
                size: size,
                opacity: opacity,
                originX: originX,
                originY: originY,
                amplitudeX: amplitudeX,
                amplitudeY: amplitudeY,
                speedX: speedX,
                speedY: speedY,
                phaseX: phaseX,
                phaseY: phaseY,
                rotationSpeed: rotationSpeed,
                rotationPhase: rotationPhase
            )
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
