import SwiftUI
import Textual

struct MarkdownPreviewDocument: Identifiable, Equatable {
    let sourcePath: String
    let title: String
    let markdown: String

    var id: String { sourcePath }
}

struct MarkdownPreviewPage: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let document: MarkdownPreviewDocument
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                StructuredText(markdown: document.markdown)
                    .textual.structuredTextStyle(.gitHub)
                    .textual.textSelection(.enabled)
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(OrbitaTheme.canvas)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .orbitaIconControlSurface()
            }
            .buttonStyle(.plain)
            .help(L("main.markdownPreview.back"))
            .accessibilityLabel(L("main.markdownPreview.back"))

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(document.sourcePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Label(L("markdown.preview.engine"), systemImage: "doc.richtext")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .orbitaControlSurface(cornerRadius: 10)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 18)
    }
}
