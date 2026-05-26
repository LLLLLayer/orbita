import Foundation
import OrbitaCore

struct UserDirectoryAccessPreflightResult: Sendable {
    var checkedURLs: [URL]
    var deniedURLs: [URL]
}

enum UserDirectoryAccessPreflight {
    static func run(
        options: ScanOptions = ScanOptions(),
        projectLibraryStore: ProjectLibraryStore = ProjectLibraryStore(),
        fileManager: FileManager = .default
    ) -> UserDirectoryAccessPreflightResult {
        let candidates = candidateURLs(
            options: options,
            projectLibraryStore: projectLibraryStore,
            fileManager: fileManager
        )
        var checked: [URL] = []
        var denied: [URL] = []

        for url in candidates {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            checked.append(url)
            if !touch(url, fileManager: fileManager) {
                denied.append(url)
            }
        }

        return UserDirectoryAccessPreflightResult(checkedURLs: checked, deniedURLs: denied)
    }

    private static func candidateURLs(
        options: ScanOptions,
        projectLibraryStore: ProjectLibraryStore,
        fileManager: FileManager
    ) -> [URL] {
        var urls: [URL] = []

        append(options.codexConfigURL, to: &urls)
        append(options.codexConfigURL.deletingLastPathComponent(), to: &urls)
        append(options.codexConfigURL.deletingLastPathComponent().appendingPathComponent("hooks.json"), to: &urls)
        append(options.codexPluginCacheRoot, to: &urls)
        append(options.codexPluginCacheRoot.deletingLastPathComponent(), to: &urls)
        append(options.claudeInstalledPluginsURL, to: &urls)
        append(options.claudeInstalledPluginsURL.deletingLastPathComponent(), to: &urls)
        append(options.claudeInstalledPluginsURL.deletingLastPathComponent().deletingLastPathComponent(), to: &urls)
        append(options.skillsGlobalLockURL, to: &urls)
        append(options.skillsGlobalLockURL.deletingLastPathComponent(), to: &urls)
        append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".orbita/this-mac", isDirectory: true),
            to: &urls
        )

        for settingsURL in options.claudeSettingsURLs {
            append(settingsURL, to: &urls)
            append(settingsURL.deletingLastPathComponent(), to: &urls)
        }

        for skillRoot in options.userSkillRoots {
            append(skillRoot, to: &urls)
            append(skillRoot.deletingLastPathComponent(), to: &urls)
        }

        if let library = try? projectLibraryStore.load() {
            if let lastProjectPath = library.lastProjectPath {
                append(URL(fileURLWithPath: lastProjectPath, isDirectory: true), to: &urls)
            }
            for project in library.projects {
                append(URL(fileURLWithPath: project.path, isDirectory: true), to: &urls)
            }
        }

        return deduplicated(urls, fileManager: fileManager)
    }

    private static func append(_ url: URL, to urls: inout [URL]) {
        urls.append(url.standardizedFileURL)
    }

    private static func deduplicated(_ urls: [URL], fileManager: FileManager) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let path = canonicalPath(for: url, fileManager: fileManager)
            guard seen.insert(path).inserted else { continue }
            result.append(URL(fileURLWithPath: path))
        }
        return result
    }

    private static func canonicalPath(for url: URL, fileManager: FileManager) -> String {
        let path = url.path
        if fileManager.fileExists(atPath: path) {
            return url.resolvingSymlinksInPath().path
        }
        return path
    }

    private static func touch(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return true
        }

        if isDirectory.boolValue {
            do {
                _ = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants]
                )
                return true
            } catch {
                return fileManager.isReadableFile(atPath: url.path)
            }
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return true
        } catch {
            return false
        }
    }
}

extension URL {
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
