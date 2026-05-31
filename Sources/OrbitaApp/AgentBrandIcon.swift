import AppKit
import SwiftUI

/// Icon for a configured agent tab/avatar: a bundled brand SVG for the flagship agents (codex/claude/trae),
/// otherwise a unified sports-style SF Symbol.
struct AgentBrandIcon: View {
    let agent: AgentSelection
    var size: CGFloat = 16
    var isSelected = false

    var body: some View {
        AgentGlyph(
            assetName: agent.brandIconAssetName,
            seed: agent.id.isEmpty ? agent.displayName : agent.id,
            displayName: agent.displayName,
            size: size,
            isSelected: isSelected
        )
        .accessibilityHidden(true)
    }
}

/// Brand-SVG-or-sports-symbol glyph, decoupled from `AgentSelection` so the Add-agent picker can render the
/// same icon for a `SkillsAgentDefinition`. (`displayName` is retained for call-site compatibility.)
struct AgentGlyph: View {
    let assetName: String?
    let seed: String
    var displayName: String = ""
    var size: CGFloat = 16
    var isSelected = false

    var body: some View {
        if let assetName, let image = AgentBrandIconStore.image(forAssetName: assetName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : Color.primary)
                .frame(width: size, height: size)
        } else {
            AgentSportIcon(seed: seed, size: size, isSelected: isSelected)
        }
    }
}

/// Unified fallback icon for any agent without a brand SVG. A curated symbol wins when one exists
/// (e.g. `.agents` → a connected-node mesh); otherwise a sports-themed SF Symbol from the `figure.*`
/// athletic family, chosen deterministically per agent. Rendered plain in the control foreground
/// colour — no background tile.
struct AgentSportIcon: View {
    let seed: String
    var size: CGFloat = 16
    var isSelected = false

    var body: some View {
        Image(systemName: AgentGlyphSymbol.fallbackName(for: seed))
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : Color.primary)
            .frame(width: size, height: size)
    }
}

/// Resolves the non-brand glyph symbol for a seed: a hand-picked symbol for known built-in agents
/// that read poorly as a random sports figure, falling back to the deterministic sports symbol.
/// `.agents` (the cross-agent workspace) gets `point.3.connected.trianglepath.dotted` — a geeky mesh
/// of linked nodes that mirrors its semantic `systemImage`.
enum AgentGlyphSymbol {
    private static let curated: [String: String] = [
        "agents": "point.3.connected.trianglepath.dotted"
    ]

    static func fallbackName(for seed: String) -> String {
        if let curated = curated[normalizedID(seed)] {
            return curated
        }
        return AgentSportSymbol.name(for: seed)
    }

    private static func normalizedID(_ seed: String) -> String {
        for prefix in ["built-in:", "skills-agent:"] where seed.hasPrefix(prefix) {
            return String(seed.dropFirst(prefix.count))
        }
        return seed
    }
}

/// Deterministic seed → sports SF Symbol mapping. Every name is from the unified `figure.*` athletic family
/// so the whole set reads as one consistent style. Seeds may arrive prefixed (`built-in:` / `skills-agent:`);
/// normalise first so an agent keeps the same symbol across the tab strip and the Add picker.
enum AgentSportSymbol {
    static let symbols: [String] = [
        "figure.run", "figure.basketball", "figure.soccer", "figure.tennis", "figure.baseball",
        "figure.golf", "figure.skiing.downhill", "figure.snowboarding", "figure.surfing", "figure.climbing",
        "figure.boxing", "figure.indoor.cycle", "figure.bowling", "figure.badminton", "figure.volleyball",
        "figure.gymnastics", "figure.skateboarding", "figure.fencing", "figure.archery", "figure.cricket",
        "figure.table.tennis", "figure.handball", "figure.rugby", "figure.kickboxing", "figure.jumprope",
        "figure.martial.arts", "figure.disc.sports", "figure.australian.football", "figure.elliptical",
        "figure.strengthtraining.traditional", "figure.hiking", "figure.dance"
    ]

    static func name(for seed: String) -> String {
        let id = normalizedID(seed)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return symbols[Int(hash % UInt64(symbols.count))]
    }

    private static func normalizedID(_ seed: String) -> String {
        for prefix in ["built-in:", "skills-agent:"] where seed.hasPrefix(prefix) {
            return String(seed.dropFirst(prefix.count))
        }
        return seed
    }
}

@MainActor
enum AgentBrandIconStore {
    private static var cache: [String: NSImage] = [:]

    static func image(forAssetName assetName: String) -> NSImage? {
        if let cached = cache[assetName] {
            return cached
        }
        guard let url = resourceURL(for: assetName),
              let image = NSImage(contentsOf: url)?.copy() as? NSImage else {
            return nil
        }
        cache[assetName] = image
        return image
    }

    private static func resourceURL(for assetName: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(
            forResource: assetName,
            withExtension: "svg",
            subdirectory: "AgentIcons"
        ) {
            return url
        }
        #endif

        if let url = Bundle.main.url(forResource: assetName, withExtension: "svg", subdirectory: "AgentIcons") {
            return url
        }
        if let url = Bundle.main.url(forResource: assetName, withExtension: "svg", subdirectory: "Resources/AgentIcons") {
            return url
        }
        return Bundle.main.url(forResource: assetName, withExtension: "svg")
    }

    /// Bundled brand asset for a Skills-CLI agent id, when we ship one. Only the flagship three keep a brand
    /// SVG; everything else (including Cursor) uses the unified sports glyph.
    static func assetName(forAgentID id: String) -> String? {
        switch id {
        case "codex": return "codex"
        case "claude-code": return "claude"
        case "trae": return "trae"
        default: return nil
        }
    }
}

/// `NSImage` form of an agent glyph, for AppKit-backed surfaces — notably SwiftUI `Menu` items, which only
/// render an image + title. Brand SVGs come straight from the store; the sports glyph is the SF Symbol
/// rendered as a template image so it adopts the menu's label colour (unified, no background).
/// (`displayName` is retained for call-site compatibility.)
@MainActor
enum AgentGlyphImage {
    private static var cache: [String: NSImage] = [:]

    static func nsImage(assetName: String?, seed: String, displayName: String = "", size: CGFloat = 16) -> NSImage {
        if let assetName, let image = AgentBrandIconStore.image(forAssetName: assetName) {
            return image
        }
        let symbol = AgentGlyphSymbol.fallbackName(for: seed)
        if let cached = cache[symbol] {
            return cached
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        cache[symbol] = image
        return image
    }
}
