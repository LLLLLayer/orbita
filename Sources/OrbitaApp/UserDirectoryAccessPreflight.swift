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
            switch probe(url, fileManager: fileManager) {
            case .allowed:
                checked.append(url)
            case .denied:
                checked.append(url)
                denied.append(url)
            case .missing:
                continue
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

        return deduplicatedPreflightURLs(urls, fileManager: fileManager)
    }

    private static func append(_ url: URL, to urls: inout [URL]) {
        urls.append(url.standardizedFileURL)
    }

    private static func deduplicatedPreflightURLs(_ urls: [URL], fileManager: FileManager) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let preflightURL = privacyPromptRoot(for: url, fileManager: fileManager) ?? url.standardizedFileURL
            let path = preflightURL.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(URL(fileURLWithPath: path))
        }
        return result
    }

    private static func privacyPromptRoot(for url: URL, fileManager: FileManager) -> URL? {
        let path = url.standardizedFileURL.path
        return protectedPromptRoots(fileManager: fileManager).first { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    private static func protectedPromptRoots(fileManager: FileManager) -> [URL] {
        [
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
        ]
        .compactMap { $0?.standardizedFileURL }
    }

    private enum ProbeResult {
        case allowed
        case denied
        case missing
    }

    private static func probe(_ url: URL, fileManager: FileManager) -> ProbeResult {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }

        if isDirectory.boolValue {
            do {
                _ = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants]
                )
                return .allowed
            } catch {
                return fileManager.isReadableFile(atPath: url.path) ? .allowed : .denied
            }
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return .allowed
        } catch {
            return .denied
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
