import Foundation

public enum DoctorCheckStatus: String, Codable, Sendable {
    case ok
    case warning
    case error
}

public struct DoctorCheck: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: DoctorCheckStatus
    public var path: String?
    public var message: String

    public init(id: String, title: String, status: DoctorCheckStatus, path: String?, message: String) {
        self.id = id
        self.title = title
        self.status = status
        self.path = path
        self.message = message
    }
}

public struct DoctorReport: Codable, Sendable {
    public var schemaVersion: Int
    public var swiftVersion: String
    public var currentDirectory: String
    public var homeDirectory: String
    public var checks: [DoctorCheck]

    public init(
        schemaVersion: Int = 1,
        swiftVersion: String,
        currentDirectory: String,
        homeDirectory: String,
        checks: [DoctorCheck]
    ) {
        self.schemaVersion = schemaVersion
        self.swiftVersion = swiftVersion
        self.currentDirectory = currentDirectory
        self.homeDirectory = homeDirectory
        self.checks = checks
    }
}

public final class DoctorReportBuilder {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func report(
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        swiftVersion: String
    ) -> DoctorReport {
        let checks = [
            directoryCheck(id: "current-directory", title: "Current directory", url: URL(fileURLWithPath: currentDirectory)),
            directoryCheck(id: "codex-home", title: "Codex config directory", url: homeDirectory.appendingPathComponent(".codex")),
            directoryCheck(id: "agents-home", title: "Shared agents directory", url: homeDirectory.appendingPathComponent(".agents")),
            directoryCheck(id: "codex-skills", title: "Codex skills directory", url: homeDirectory.appendingPathComponent(".codex/skills")),
            directoryCheck(id: "agents-skills", title: ".agents skills directory", url: homeDirectory.appendingPathComponent(".agents/skills")),
            directoryCheck(id: "codex-plugin-cache", title: "Codex plugin cache", url: homeDirectory.appendingPathComponent(".codex/plugins/cache")),
            directoryCheck(id: "claude-home", title: "Claude Code config directory", url: homeDirectory.appendingPathComponent(".claude")),
            directoryCheck(id: "cursor-home", title: "Cursor config directory", url: homeDirectory.appendingPathComponent(".cursor")),
            directoryCheck(id: "trae-home", title: "Trae config directory", url: homeDirectory.appendingPathComponent(".trae")),
            directoryCheck(id: "trae-skills", title: "Trae skills directory", url: homeDirectory.appendingPathComponent(".trae/skills")),
            directoryCheck(id: "traecn-home", title: "Trae CN config directory", url: homeDirectory.appendingPathComponent(".traecn")),
            directoryCheck(id: "traecn-skills", title: "Trae CN skills directory", url: homeDirectory.appendingPathComponent(".traecn/skills")),
            fileCheck(id: "project-mcp", title: "Project MCP config", url: URL(fileURLWithPath: currentDirectory).appendingPathComponent(".mcp.json"))
        ]

        return DoctorReport(
            swiftVersion: swiftVersion,
            currentDirectory: currentDirectory,
            homeDirectory: homeDirectory.path,
            checks: checks
        )
    }

    private func directoryCheck(id: String, title: String, url: URL) -> DoctorCheck {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return DoctorCheck(id: id, title: title, status: .warning, path: url.path, message: "Path does not exist")
        }
        guard isDirectory.boolValue else {
            return DoctorCheck(id: id, title: title, status: .error, path: url.path, message: "Path exists but is not a directory")
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            return DoctorCheck(id: id, title: title, status: .error, path: url.path, message: "Directory is not readable")
        }
        guard fileManager.isWritableFile(atPath: url.path) else {
            return DoctorCheck(id: id, title: title, status: .warning, path: url.path, message: "Directory is readable but not writable")
        }
        return DoctorCheck(id: id, title: title, status: .ok, path: url.path, message: "Directory is readable and writable")
    }

    private func fileCheck(id: String, title: String, url: URL) -> DoctorCheck {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return DoctorCheck(id: id, title: title, status: .warning, path: url.path, message: "Path does not exist")
        }
        guard !isDirectory.boolValue else {
            return DoctorCheck(id: id, title: title, status: .error, path: url.path, message: "Path exists but is a directory")
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            return DoctorCheck(id: id, title: title, status: .error, path: url.path, message: "File is not readable")
        }
        return DoctorCheck(id: id, title: title, status: .ok, path: url.path, message: "File is readable")
    }
}
