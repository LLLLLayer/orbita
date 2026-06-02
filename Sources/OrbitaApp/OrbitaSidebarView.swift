import SwiftUI
import OrbitaCore
import UniformTypeIdentifiers

enum OrbitaLayoutMetrics {
    static let sidebarWidth: CGFloat = 224
    static let sidebarRailWidth: CGFloat = 64
    static let inspectorWidth: CGFloat = 340
    static let minimumWindowWidth: CGFloat = 1100
    static let minimumWindowHeight: CGFloat = 720
}

struct OrbitaSidebarView: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let projects: [ProjectRecord]
    @Binding var selection: String?
    let onCollapse: () -> Void
    let onAddProject: () -> Void
    let onSelectThisMac: () -> Void
    let onSelectProject: (ProjectRecord) -> Void
    let onRemoveProject: (ProjectRecord) -> Void
    let onPinProject: (ProjectRecord) -> Void
    let onMoveProjects: (IndexSet, Int) -> Void
    let onOpenSettings: () -> Void

    @State private var draggedProjectPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
                Button(action: onCollapse) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .orbitaIconControlSurface()
                }
                .buttonStyle(.plain)
                .help(L("sidebar.collapse"))
                .accessibilityLabel(L("sidebar.collapse"))
            }
            .frame(height: 54)
            .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 18) {
                SidebarSection(title: L("sidebar.section.environment")) {
                    SidebarNavigationRow(
                        title: L("sidebar.thismac.title"),
                        subtitle: L("sidebar.thismac.subtitle"),
                        systemImage: "desktopcomputer",
                        isSelected: selection == ProjectCapabilityStore.environmentSelectionID,
                        action: onSelectThisMac
                    )
                }

                SidebarSection(
                    title: L("sidebar.section.projects"),
                    trailing: {
                        Button(action: onAddProject) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 22, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(L("sidebar.openProject"))
                        .accessibilityLabel(L("sidebar.openProject"))
                    },
                    content: {
                        if projects.isEmpty {
                            SidebarNavigationRow(
                                title: L("sidebar.openProject.row.title"),
                                subtitle: L("sidebar.openProject.row.subtitle"),
                                systemImage: "folder.badge.plus",
                                isSelected: false,
                                action: onAddProject
                            )
                        } else {
                            VStack(spacing: 4) {
                                ForEach(projects) { project in
                                    ProjectSidebarRow(
                                        project: project,
                                        isSelected: selection == project.path,
                                        canPin: project.path != projects.first?.path,
                                        onSelect: {
                                            selection = project.path
                                            onSelectProject(project)
                                        },
                                        onPin: {
                                            onPinProject(project)
                                        },
                                        onRemove: {
                                            onRemoveProject(project)
                                        }
                                    )
                                    .onDrag {
                                        draggedProjectPath = project.path
                                        return NSItemProvider(object: project.path as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: ProjectReorderDropDelegate(
                                            project: project,
                                            projects: projects,
                                            draggedProjectPath: $draggedProjectPath,
                                            onMoveProjects: onMoveProjects
                                        )
                                    )
                                    .help(L("sidebar.dragToReorder"))
                                }
                            }
                        }
                    }
                )
            }

            Spacer(minLength: 16)

            SidebarSettingsRow(
                title: L("settings.title"),
                subtitle: L("sidebar.settings.subtitle"),
                systemImage: "gearshape",
                action: onOpenSettings
            )
            .padding(.bottom, 16)
        }
        .frame(width: OrbitaLayoutMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(OrbitaTheme.sidebarBackground)
    }
}

struct OrbitaSidebarRail: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let selection: String?
    var updateAvailable: Bool = false
    let onExpand: () -> Void
    let onSelectThisMac: () -> Void
    let onAddProject: () -> Void
    let onOpenSettings: () -> Void
    var onUpdate: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RailButton(systemImage: "sidebar.left", isSelected: false, help: L("sidebar.expand"), action: onExpand)
            }
            .frame(height: 86, alignment: .bottom)
            .padding(.bottom, 8)

            if updateAvailable {
                RailUpdateButton(action: onUpdate)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack(spacing: 8) {
                RailButton(systemImage: "desktopcomputer", isSelected: selection == ProjectCapabilityStore.environmentSelectionID, help: L("sidebar.thismac.title"), action: onSelectThisMac)
                RailButton(systemImage: "folder.badge.plus", isSelected: false, help: L("sidebar.openProject"), action: onAddProject)
                Spacer(minLength: 12)
                RailButton(systemImage: "gearshape", isSelected: false, help: L("settings.title"), action: onOpenSettings)
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(width: OrbitaLayoutMetrics.sidebarRailWidth)
        .frame(maxHeight: .infinity)
        .background(OrbitaTheme.sidebarBackground)
        .animation(.snappy(duration: 0.22), value: updateAvailable)
    }
}

private struct ProjectReorderDropDelegate: DropDelegate {
    let project: ProjectRecord
    let projects: [ProjectRecord]
    @Binding var draggedProjectPath: String?
    let onMoveProjects: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedProjectPath,
              draggedProjectPath != project.path,
              let fromIndex = projects.firstIndex(where: { $0.path == draggedProjectPath }),
              let toIndex = projects.firstIndex(where: { $0.path == project.path })
        else {
            return
        }

        withAnimation(.snappy(duration: 0.16)) {
            onMoveProjects(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedProjectPath = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct SidebarSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing()
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 24)
            .padding(.trailing, 12)
            content()
        }
    }
}

private struct ProjectSidebarRow: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let project: ProjectRecord
    let isSelected: Bool
    let canPin: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? OrbitaTheme.elevatedSurface : Color.clear)
                .shadow(color: isSelected ? OrbitaTheme.selectedShadow : Color.clear, radius: 8, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? OrbitaTheme.border : Color.clear)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(action: onPin) {
                Label(L("sidebar.menu.pinToTop"), systemImage: "pin")
            }
            .disabled(!canPin)
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label(L("sidebar.menu.delete"), systemImage: "trash")
            }
        }
        .accessibilityAddTraits(.isButton)
        .animation(.snappy(duration: 0.16), value: isSelected)
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? OrbitaTheme.elevatedSurface : Color.clear)
                    .shadow(color: isSelected ? OrbitaTheme.selectedShadow : Color.clear, radius: 8, x: 0, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? OrbitaTheme.border : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .animation(.snappy(duration: 0.16), value: isSelected)
    }
}

private struct SidebarSettingsRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .orbitaIconControlSurface()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }
}

private struct RailButton: View {
    let systemImage: String
    let isSelected: Bool
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .orbitaIconControlSurface(selected: isSelected)
        }
        .buttonStyle(.plain)
        .frame(width: OrbitaLayoutMetrics.sidebarRailWidth, height: 44)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The collapsed-sidebar "update available" affordance: a tinted download glyph with a notification
/// dot, shown only when a silent appcast probe found a newer build. Clicking opens Sparkle's install
/// flow. Mirrors `RailButton`'s footprint so it sits flush in the rail.
private struct RailUpdateButton: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .orbitaIconControlSurface(selected: false)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(OrbitaTheme.sidebarBackground, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
        }
        .buttonStyle(.plain)
        .frame(width: OrbitaLayoutMetrics.sidebarRailWidth, height: 44)
        .help(L("sidebar.update.available"))
        .accessibilityLabel(L("sidebar.update.available"))
    }
}
