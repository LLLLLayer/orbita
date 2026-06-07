import Foundation

public struct ProjectRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var lastOpenedAt: String

    public init(name: String, path: String, lastOpenedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.name = name
        self.path = path
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct ProjectLibrary: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var lastProjectPath: String?
    public var projects: [ProjectRecord]

    public init(schemaVersion: Int = ProjectLibrary.currentSchemaVersion, lastProjectPath: String? = nil, projects: [ProjectRecord] = []) {
        self.schemaVersion = schemaVersion
        self.lastProjectPath = lastProjectPath
        self.projects = projects
    }

    public mutating func upsert(projectRoot: URL) {
        let normalizedPath = normalizedPath(projectRoot)
        let name = projectRoot.lastPathComponent.isEmpty ? normalizedPath : projectRoot.lastPathComponent
        if let index = projects.firstIndex(where: { $0.path == normalizedPath }) {
            projects[index].name = name
            projects[index].lastOpenedAt = ISO8601DateFormatter().string(from: Date())
        } else {
            projects.append(ProjectRecord(name: name, path: normalizedPath))
        }
        lastProjectPath = normalizedPath
    }

    public mutating func remove(projectPath: String) {
        let normalized = normalizedPath(URL(fileURLWithPath: projectPath))
        projects.removeAll { $0.path == normalized }
        if lastProjectPath == normalized {
            lastProjectPath = projects.first?.path
        }
    }

    public mutating func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        let indexes = source.filter { projects.indices.contains($0) }.sorted()
        guard !indexes.isEmpty else { return }
        let moved = indexes.map { projects[$0] }
        var adjustedDestination = destination
        for index in indexes.reversed() {
            projects.remove(at: index)
            if index < adjustedDestination {
                adjustedDestination -= 1
            }
        }
        let insertionIndex = min(max(adjustedDestination, 0), projects.count)
        projects.insert(contentsOf: moved, at: insertionIndex)
    }

    public mutating func moveProjectToTop(projectPath: String) {
        let normalized = normalizedPath(URL(fileURLWithPath: projectPath))
        guard let index = projects.firstIndex(where: { $0.path == normalized }), index > 0 else {
            return
        }
        let project = projects.remove(at: index)
        projects.insert(project, at: 0)
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

public final class ProjectLibraryStore {
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

    public func load() throws -> ProjectLibrary {
        let url = libraryURL
        guard fileManager.fileExists(atPath: url.path) else {
            return ProjectLibrary()
        }
        // Genuine read errors (e.g. permission denied) still propagate so a
        // transient failure does not trigger backup-and-wipe.
        let data = try Data(contentsOf: url)
        do {
            let library = try decoder.decode(ProjectLibrary.self, from: data)
            guard library.schemaVersion == ProjectLibrary.currentSchemaVersion else {
                quarantineCorruptLibrary(at: url)
                return ProjectLibrary()
            }
            return library
        } catch {
            // Corrupt JSON: move it aside so a subsequent save never silently
            // clobbers data we failed to read, then start fresh.
            quarantineCorruptLibrary(at: url)
            return ProjectLibrary()
        }
    }

    public func save(_ library: ProjectLibrary) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try encoder.encode(library)
        try data.write(to: libraryURL, options: .atomic)
    }

    private var libraryURL: URL {
        root.appendingPathComponent("projects.json")
    }

    /// Best-effort move of an unreadable/incompatible library file aside so the original data survives a
    /// subsequent atomic save. `projects.json.bak` is the only non-regenerable user data Orbita keeps, so
    /// quarantine must be non-destructive — see `OrbitaStateBackup`.
    private func quarantineCorruptLibrary(at url: URL) {
        OrbitaStateBackup.quarantine(url, fileManager: fileManager)
    }
}

/// Moves an unreadable/incompatible Orbita state file aside to a `.bak` sidecar. Shared by
/// `ProjectLibraryStore` (data-grade) and `CapabilitySnapshotStore` (cache) so the two never drift apart.
///
/// Two correctness rules the previous per-store copies lacked:
///   1. **Never clobber an existing backup.** The first quarantine uses `<file>.bak`; a *second* one (e.g.
///      after the post-quarantine empty/near-empty re-save itself fails to decode) uses `<file>.bak.1`,
///      `.bak.2`, … — so the original good copy in `<file>.bak` is never overwritten with worse data.
///   2. **Move, never pre-delete.** We never `removeItem` a backup before moving; a failed move therefore
///      can't leave the live file gone with its backup already deleted.
enum OrbitaStateBackup {
    static func quarantine(_ url: URL, fileManager: FileManager) {
        var backup = url.appendingPathExtension("bak")
        var counter = 1
        while fileManager.fileExists(atPath: backup.path) {
            backup = url.appendingPathExtension("bak.\(counter)")
            counter += 1
        }
        try? fileManager.moveItem(at: url, to: backup)
    }
}
