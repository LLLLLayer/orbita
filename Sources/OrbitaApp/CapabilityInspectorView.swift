import SwiftUI
import Foundation
import AppKit
import OrbitaCore

struct CapabilityInspectorView: View {
    let capability: Capability?
    let onClose: () -> Void
    let onEnable: (Capability) -> Void
    let onDisable: (Capability) -> Void
    let onDelete: (Capability) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("Hide inspector")
            }
            .padding(.top, 28)
            .padding(.leading, 24)
            .padding(.trailing, 22)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                if let capability {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: CapabilityVisuals.iconName(for: capability.type))
                                .font(.system(size: 19, weight: .medium))
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(capability.name)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                Text(capability.type.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        InspectorSection {
                            InspectorField("Scope", value: capability.scope.rawValue)
                            InspectorField("Status", value: CapabilityVisuals.statusLabel(for: capability))
                            InspectorField("Access", value: CapabilityDisplayText.accessSummary(for: capability.risks))
                            InspectorPathField("Source", path: sourcePath(for: capability))
                            if let childCount = capability.metadata["childCount"] {
                                InspectorField("Children", value: childCount)
                            }
                        }

                        StatusReasonSection(capability: capability)

                        if canApplyActions(to: capability) {
                            HStack(spacing: 8) {
                                Button {
                                    onEnable(capability)
                                } label: {
                                    Label("Enable", systemImage: "checkmark.circle")
                                }
                                Button {
                                    onDisable(capability)
                                } label: {
                                    Label("Disable", systemImage: "minus.circle")
                                }
                                Button(role: .destructive) {
                                    onDelete(capability)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 2)
                        }

                        if let markdownPath = markdownPreviewPath(for: capability) {
                            MarkdownPreviewCard(sourcePath: markdownPath)
                        }
                    }
                    .padding(.top, 18)
                    .padding(.leading, 24)
                    .padding(.trailing, 24)
                    .padding(.bottom, 18)
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "sidebar.right",
                        description: Text("Select a capability to inspect source, scope, access, and loading path.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .padding(24)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
    }

    private func sourcePath(for capability: Capability) -> String {
        if !capability.source.path.isEmpty {
            return capability.source.path
        }
        if let path = capability.metadata["sourcePath"], !path.isEmpty {
            return path
        }
        return "-"
    }

    private func canApplyActions(to capability: Capability) -> Bool {
        capability.source.kind != "virtual-plugin"
    }

    private func markdownPreviewPath(for capability: Capability) -> String? {
        let path = sourcePath(for: capability)
        guard path != "-", path.lowercased().hasSuffix(".md") else {
            return nil
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return path
    }
}

private struct StatusReasonSection: View {
    let capability: Capability

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CapabilityVisuals.statusColor(for: capability))
                        .frame(width: 8, height: 8)
                    Text("Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(dotLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(reasons) { reason in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: reason.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(reason.color)
                                .frame(width: 14, alignment: .center)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(reason.title)
                                    .font(.caption.weight(.semibold))
                                Text(reason.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var dotLabel: String {
        if capability.statuses.contains(.broken) {
            return "Broken"
        }
        if capability.statuses.contains(.drifted) || capability.statuses.contains(.shadowed) {
            return "Needs attention"
        }
        if capability.statuses.contains(.risky) {
            return "Review needed"
        }
        return "Ready"
    }

    private var reasons: [StatusReason] {
        var items: [StatusReason] = []

        if capability.statuses.contains(.broken) {
            items.append(StatusReason(
                title: "Broken source",
                detail: "Orbita found a record for this capability, but the source path is missing, unreadable, or could not be resolved.",
                systemImage: "xmark.octagon",
                color: .red
            ))
        }

        if capability.statuses.contains(.shadowed) {
            items.append(StatusReason(
                title: "Overridden by a higher-priority scope",
                detail: "Another capability with the same type and name exists in a higher-priority scope. Priority is project, user, installed, then environment.",
                systemImage: "square.on.square",
                color: .orange
            ))
        }

        if capability.statuses.contains(.drifted) {
            items.append(StatusReason(
                title: "Drift detected",
                detail: driftDetail,
                systemImage: "arrow.triangle.branch",
                color: .orange
            ))
        }

        if capability.statuses.contains(.risky) {
            items.append(StatusReason(
                title: "Access needs review",
                detail: "This capability requests \(CapabilityDisplayText.accessSummary(for: capability.risks)).",
                systemImage: "exclamationmark.triangle",
                color: .yellow
            ))
        }

        if capability.statuses.contains(.disabled) {
            items.append(StatusReason(
                title: "Disabled in .agents",
                detail: "The .agents manifest marks this capability as disabled.",
                systemImage: "minus.circle",
                color: .secondary
            ))
        }

        if capability.statuses.contains(.duplicate) {
            items.append(StatusReason(
                title: "Duplicate name",
                detail: "Orbita found more than one capability with this type and name.",
                systemImage: "doc.on.doc",
                color: .secondary
            ))
        }

        if items.isEmpty {
            items.append(StatusReason(
                title: "Ready",
                detail: "Orbita found this capability and did not detect broken links, drift, overrides, or review flags.",
                systemImage: "checkmark.circle",
                color: .green
            ))
        }

        return items
    }

    private var driftDetail: String {
        if let reason = capability.metadata["driftReason"], !reason.isEmpty {
            return reason
        }
        return "A capability with the same type and name exists in multiple places, and the content hash is different."
    }
}

private struct StatusReason: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
}

private struct InspectorSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.secondary.opacity(0.1))
        }
    }
}

private struct InspectorField: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value.isEmpty ? "-" : value)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct InspectorPathField: View {
    let title: String
    let path: String

    init(_ title: String, path: String) {
        self.title = title
        self.path = path
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .padding(.top, 1)

            Text(path.isEmpty ? "-" : path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            SourceFolderButton(path: path)
        }
    }
}

private struct SourceFolderButton: View {
    let path: String

    var body: some View {
        Button {
            openInFinder()
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help("Open source folder")
        .disabled(!canOpen)
        .opacity(canOpen ? 1 : 0.45)
    }

    private var canOpen: Bool {
        resolvedTargetURL() != nil
    }

    private func openInFinder() {
        guard let targetURL = resolvedTargetURL() else {
            return
        }
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            NSWorkspace.shared.open(targetURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func resolvedTargetURL() -> URL? {
        guard path != "-", !path.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let parent = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else {
            return nil
        }
        return parent
    }
}

private struct MarkdownPreviewCard: View {
    let sourcePath: String

    @State private var previewState: MarkdownPreviewState = .loading

    var body: some View {
        InspectorSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Markdown Preview", systemImage: "doc.richtext")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                switch previewState {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .unavailable:
                    Text("No markdown preview available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case let .rendered(markdown):
                    Text(markdown)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .raw(text):
                    Text(text)
                        .font(.callout.monospaced())
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case let .failed(message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: sourcePath) {
            previewState = .loading
            previewState = MarkdownPreviewState.load(path: sourcePath)
        }
    }
}

private enum MarkdownPreviewState {
    case loading
    case unavailable
    case rendered(AttributedString)
    case raw(String)
    case failed(String)

    static func load(path: String) -> MarkdownPreviewState {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .unavailable
        }

        do {
            let rawText = try String(contentsOfFile: path, encoding: .utf8)
            let markdown = trimmedMarkdown(rawText)
            guard !markdown.isEmpty else {
                return .unavailable
            }

            do {
                let rendered = try AttributedString(
                    markdown: markdown,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .full,
                        failurePolicy: .returnPartiallyParsedIfPossible
                    )
                )
                return .rendered(rendered)
            } catch {
                return .raw(markdown)
            }
        } catch {
            return .failed("Unable to read markdown: \(error.localizedDescription)")
        }
    }

    private static func trimmedMarkdown(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let body = stripFrontmatter(from: normalized)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 80_000
        guard body.count > maxLength else {
            return body
        }
        let endIndex = body.index(body.startIndex, offsetBy: maxLength)
        return String(body[..<endIndex]) + "\n\nPreview truncated."
    }

    private static func stripFrontmatter(from text: String) -> String {
        guard text.hasPrefix("---\n") else {
            return text
        }
        let searchStart = text.index(text.startIndex, offsetBy: 4)
        guard let closingRange = text.range(of: "\n---\n", range: searchStart..<text.endIndex) else {
            return text
        }
        return String(text[closingRange.upperBound...])
    }
}
