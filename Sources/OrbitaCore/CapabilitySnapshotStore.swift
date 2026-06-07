import CryptoKit
import Foundation

public struct CapabilitySnapshot: Codable, Sendable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var capturedAt: String
    public var projectRoot: String
    public var graph: CapabilityGraph

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        capturedAt: String = ISO8601DateFormatter().string(from: Date()),
        projectRoot: String,
        graph: CapabilityGraph
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.projectRoot = projectRoot
        self.graph = graph
    }
}

public final class CapabilitySnapshotStore {
    private let root: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".orbita"),
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(projectRoot: URL) throws -> CapabilitySnapshot? {
        let url = snapshotURL(for: projectRoot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        // Genuine read errors (e.g. permission denied) still propagate so a
        // transient failure does not trigger backup-and-discard.
        let data = try Data(contentsOf: url)
        let snapshot: CapabilitySnapshot
        do {
            snapshot = try decoder.decode(CapabilitySnapshot.self, from: data)
        } catch {
            // Corrupt snapshot JSON: move it aside before the next save() clobbers
            // it, mirroring ProjectLibraryStore. The snapshot is a regenerable
            // cache, so we still return nil and re-scan — but we keep a forensic
            // copy instead of silently discarding (the old behavior).
            quarantineStaleSnapshot(at: url)
            return nil
        }
        guard snapshot.schemaVersion == CapabilitySnapshot.currentSchemaVersion else {
            // Schema bump: the on-disk snapshot predates the current shape.
            // Back it up before discarding so a buggy migration is recoverable.
            quarantineStaleSnapshot(at: url)
            return nil
        }
        guard snapshot.projectRoot == normalizedPath(projectRoot) else { return nil }
        return snapshot
    }

    public func save(_ graph: CapabilityGraph) throws {
        let projectRoot = URL(fileURLWithPath: graph.projectRoot)
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)

        let snapshot = CapabilitySnapshot(
            projectRoot: normalizedPath(projectRoot),
            graph: graph
        )
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL(for: projectRoot), options: .atomic)
    }

    private func snapshotURL(for projectRoot: URL) -> URL {
        root
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent("\(cacheKey(for: projectRoot)).json")
    }

    private func cacheKey(for projectRoot: URL) -> String {
        let path = normalizedPath(projectRoot)
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Best-effort move of an unreadable/incompatible snapshot file to a `.bak`
    /// sidecar so a subsequent atomic save never silently clobbers the only copy
    /// we failed to read. Overwrites any prior `.bak` (one stale copy per project).
    private func quarantineStaleSnapshot(at url: URL) {
        let backup = url.appendingPathExtension("bak")
        try? fileManager.removeItem(at: backup)
        try? fileManager.moveItem(at: url, to: backup)
    }
}
