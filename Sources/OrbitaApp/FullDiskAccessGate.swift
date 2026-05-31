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
            return .denied(L("permission.denied.noProbes"))
        }

        return .denied(L("permission.denied.notYet"))
    }

    private static func protectedProbeURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        ]
    }
}

struct FullDiskAccessOnboardingView: View {
    @ObservedObject private var localization = LocalizationManager.shared
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
                        Text(L("permission.title"))
                            .font(.title2.weight(.semibold))
                        Text(L("permission.subtitle.reads"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("permission.subtitle.skip"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    PermissionStep(number: 1, title: L("permission.step1.title"), detail: L("permission.step1.detail"))
                    PermissionStep(number: 2, title: L("permission.step2.title"), detail: L("permission.step2.detail"))
                    PermissionStep(number: 3, title: L("permission.step3.title"), detail: L("permission.step3.detail"))
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
                        Label(L("permission.button.openSettings"), systemImage: "gear")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: onContinueWithoutAccess) {
                        Label(isPreflightingDirectoryAccess ? L("permission.button.checking") : L("permission.button.skip"), systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isPreflightingDirectoryAccess)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label(L("permission.button.quit"), systemImage: "power")
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

/// A slow, decorative drift of faint capability glyphs behind the onboarding / permission cards.
/// Rendered in a single GPU-backed `Canvas` (drawn on a background thread) rather than as N separate
/// animated `Image` views: at 30fps the old approach re-diffed and re-laid-out 14 views per frame on the
/// main thread, which stuttered. The Canvas draws every particle in one pass, so it stays smooth.
struct FloatingIconBackdrop: View {
    private static let icons: [String] = [
        "shippingbox",
        "wand.and.stars",
        "person.2",
        "terminal",
        "server.rack",
        "link",
        "square.grid.2x2"
    ]

    /// Symbols are resolved once at this point size, then scaled per particle in the draw pass.
    private static let baseSymbolSize: CGFloat = 64

    private let particles: [Particle]

    init() {
        particles = Self.makeParticles()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { graphics, size in
                for particle in particles {
                    guard let resolved = graphics.resolveSymbol(id: particle.symbol) else { continue }
                    let point = particle.position(at: t, in: size)
                    let scale = particle.size / Self.baseSymbolSize
                    var layer = graphics
                    layer.opacity = particle.opacity
                    layer.translateBy(x: point.x, y: point.y)
                    layer.rotate(by: .degrees(particle.rotation(at: t)))
                    layer.scaleBy(x: scale, y: scale)
                    layer.draw(resolved, at: .zero, anchor: .center)
                }
            } symbols: {
                ForEach(Self.icons, id: \.self) { name in
                    Image(systemName: name)
                        .font(.system(size: Self.baseSymbolSize, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.primary)
                        .tag(name)
                }
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
