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

    /// Best-effort move of an unreadable/incompatible library file to a
    /// `.bak` sidecar so the original data survives a subsequent atomic save.
    private func quarantineCorruptLibrary(at url: URL) {
        let backup = url.appendingPathExtension("bak")
        try? fileManager.removeItem(at: backup)
        try? fileManager.moveItem(at: url, to: backup)
    }
}
