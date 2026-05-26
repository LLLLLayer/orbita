import AppKit
import SwiftUI

struct AgentBrandIcon: View {
    let agent: AgentSelection
    var size: CGFloat = 16
    var isSelected = false

    var body: some View {
        Group {
            if let image = AgentBrandIconStore.image(for: agent) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: agent.systemImage)
                    .font(.system(size: size, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .foregroundStyle(isSelected ? OrbitaTheme.prominentControlForeground : Color.primary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum AgentBrandIconStore {
    private static var cache: [String: NSImage] = [:]
    private static let templateAssets: Set<String> = ["claude", "cursor"]

    static func image(for agent: AgentSelection) -> NSImage? {
        guard let assetName = agent.brandIconAssetName else {
            return nil
        }
        if let cached = cache[assetName] {
            return cached
        }
        guard let url = Bundle.module.url(
            forResource: assetName,
            withExtension: "svg",
            subdirectory: "AgentIcons"
        ),
              let image = NSImage(contentsOf: url)?.copy() as? NSImage else {
            return nil
        }
        image.isTemplate = templateAssets.contains(assetName)
        cache[assetName] = image
        return image
    }
}
