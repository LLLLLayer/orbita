import Foundation

/// Orbita's scope-correct, self-describing "disabled store" — the destructive-move FALLBACK used only for
/// capabilities whose host has **no native disable** (e.g. Trae/Cursor skills). It replaces the former
/// `.orbita/cache/disabled` location and fixes three defects that location had:
///
///   1. **Scope is preserved.** A source under the user home quarantines under the user's own
///      `~/.orbita/disabled`, NOT into whatever project happens to be open; a source under the project
///      quarantines under `<repo>/.orbita/disabled`. A machine-wide skill is never demoted into one repo
///      and stranded there.
///   2. **It is a DATA-grade store, never a "cache".** It holds the only copy of restorable user content,
///      so it must never be swept like throwaway cache (and `plan --clean` never touches it).
///   3. **Every entry is self-describing.** A co-located `.orbita-restore.json` sidecar records the
///      original source path, so the disabled tile and its restore target survive even if
///      `.agents/manifest.json` is lost — no out-of-band pointer.
///
/// Path layout: `<base>/.orbita/disabled/<type>/<fnv1a(capabilityID|sourcePath)>/<sourceLeafName>` with a
/// sibling `.orbita-restore.json`. The hash keys an entry directory so two skills with the same leaf name
/// never collide, and the same (capability, source) always maps to the same entry (idempotent restore).
public enum OrbitaDisabledStore {
    public static let directoryName = "disabled"
    static let sidecarName = ".orbita-restore.json"

    public struct Entry: Sendable, Equatable {
        public var capabilityID: String
        public var name: String
        public var type: String
        public var originalSourcePath: String
        public var scope: String
        /// The quarantined source on disk.
        public var contentPath: String
        public var entryDirectory: String
    }

    /// Quarantine roots to read back, scope-aware: the project store always; the user store only when
    /// user-scope scanning is enabled.
    public static func roots(projectRoot: URL, home: URL, includeUserScope: Bool) -> [URL] {
        var roots = [storeRoot(base: projectRoot)]
        if includeUserScope {
            roots.append(storeRoot(base: home))
        }
        return roots
    }

    private static func storeRoot(base: URL) -> URL {
        base.appendingPathComponent(".orbita").appendingPathComponent(directoryName)
    }

    /// The `.orbita/disabled` store a given source quarantines into: a source under the project uses the
    /// project store; a source under the user home uses the user store; anything else falls back to the
    /// project store (still a known, guarded root). The project is checked first so a project that itself
    /// lives under the home directory still routes its own sources to the project store.
    public static func base(forSource sourcePath: String, projectRoot: URL, home: URL) -> URL {
        let source = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        let project = projectRoot.standardizedFileURL.path
        if source == project || source.hasPrefix(project + "/") {
            return storeRoot(base: projectRoot)
        }
        let userHome = home.standardizedFileURL.path
        if source == userHome || source.hasPrefix(userHome + "/") {
            return storeRoot(base: home)
        }
        return storeRoot(base: projectRoot)
    }

    public static func entryDirectory(capabilityID: String, type: String, sourcePath: String, projectRoot: URL, home: URL) -> URL {
        let standardizedSource = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        let key = fnv1a("\(capabilityID)|\(standardizedSource)")
        return base(forSource: sourcePath, projectRoot: projectRoot, home: home)
            .appendingPathComponent(type)
            .appendingPathComponent(key)
    }

    public static func contentPath(capabilityID: String, type: String, sourcePath: String, projectRoot: URL, home: URL) -> URL {
        entryDirectory(capabilityID: capabilityID, type: type, sourcePath: sourcePath, projectRoot: projectRoot, home: home)
            .appendingPathComponent(leafName(forSource: sourcePath))
    }

    public static func sidecarPath(forEntryDirectory dir: URL) -> URL {
        dir.appendingPathComponent(sidecarName)
    }

    private static func leafName(forSource sourcePath: String) -> String {
        let name = URL(fileURLWithPath: sourcePath).lastPathComponent
        return name.isEmpty ? "source" : name
    }

    /// Deterministic, hand-rolled JSON so the sidecar has no ordering/date nondeterminism.
    public static func sidecarJSON(capabilityID: String, name: String, type: String, originalSourcePath: String, scope: String) -> String {
        func esc(_ value: String) -> String {
            var out = ""
            for scalar in value.unicodeScalars {
                switch scalar {
                case "\\": out += "\\\\"
                case "\"": out += "\\\""
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out
        }
        return """
        {
          "schemaVersion": 1,
          "capabilityID": "\(esc(capabilityID))",
          "name": "\(esc(name))",
          "type": "\(esc(type))",
          "originalSourcePath": "\(esc(originalSourcePath))",
          "scope": "\(esc(scope))"
        }
        """
    }

    /// Read every restorable entry under the given roots whose quarantined content still exists. A sidecar
    /// whose content is gone (e.g. a leftover after a restore moved the content back) is ignored, so stale
    /// sidecars are harmless rather than surfacing phantom disabled tiles.
    public static func entries(roots: [URL], fileManager: FileManager = .default) -> [Entry] {
        var result: [Entry] = []
        for root in roots {
            guard let typeDirs = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for typeDir in typeDirs {
                guard let keyDirs = try? fileManager.contentsOfDirectory(at: typeDir, includingPropertiesForKeys: nil) else { continue }
                for keyDir in keyDirs {
                    guard let entry = readEntry(directory: keyDir, fileManager: fileManager) else { continue }
                    result.append(entry)
                }
            }
        }
        return result
    }

    private static func readEntry(directory: URL, fileManager: FileManager) -> Entry? {
        let sidecar = sidecarPath(forEntryDirectory: directory)
        guard let data = try? Data(contentsOf: sidecar),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let capabilityID = object["capabilityID"] as? String,
              let name = object["name"] as? String,
              let type = object["type"] as? String,
              let originalSourcePath = object["originalSourcePath"] as? String
        else { return nil }
        let scope = (object["scope"] as? String) ?? CapabilityScope.project.rawValue
        let content = directory.appendingPathComponent(leafName(forSource: originalSourcePath))
        guard fileManager.fileExists(atPath: content.path) else { return nil }
        return Entry(
            capabilityID: capabilityID,
            name: name,
            type: type,
            originalSourcePath: originalSourcePath,
            scope: scope,
            contentPath: content.path,
            entryDirectory: directory.path
        )
    }

    static func fnv1a(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
