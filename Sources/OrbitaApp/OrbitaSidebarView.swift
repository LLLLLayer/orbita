import SwiftUI
import OrbitaCore

struct OrbitaSidebarView: View {
    let projects: [ProjectRecord]
    @Binding var selection: String?
    let onCollapse: () -> Void
    let onAddProject: () -> Void
    let onSelectThisMac: () -> Void
    let onSelectProject: (ProjectRecord) -> Void
    let onRemoveProject: (ProjectRecord) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .help("Collapse sidebar")
            }
            .frame(height: 54)
            .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 18) {
                SidebarSection(title: "Environment") {
                    SidebarNavigationRow(
                        title: "This Mac",
                        subtitle: "User and device scope",
                        systemImage: "desktopcomputer",
                        isSelected: selection == ProjectCapabilityStore.environmentSelectionID,
                        action: onSelectThisMac
                    )
                }

                SidebarSection(
                    title: "Projects",
                    trailing: {
                        Button(action: onAddProject) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 22, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Open project")
                    },
                    content: {
                        if projects.isEmpty {
                            SidebarNavigationRow(
                                title: "Open Project...",
                                subtitle: "Choose a repository",
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
                                        onSelect: {
                                            selection = project.path
                                            onSelectProject(project)
                                        },
                                        onRemove: {
                                            onRemoveProject(project)
                                        }
                                    )
                                }
                            }
                        }
                    }
                )
            }

            Spacer(minLength: 16)

            SidebarNavigationRow(
                title: "Settings",
                subtitle: "Preferences",
                systemImage: "gearshape",
                isSelected: false,
                action: onOpenSettings
            )
            .padding(.bottom, 16)
        }
        .frame(width: 224)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }
}

struct OrbitaSidebarRail: View {
    let selection: String?
    let onExpand: () -> Void
    let onSelectThisMac: () -> Void
    let onAddProject: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            RailButton(systemImage: "sidebar.left", isSelected: false, action: onExpand)
                .help("Expand sidebar")
            RailButton(systemImage: "desktopcomputer", isSelected: selection == ProjectCapabilityStore.environmentSelectionID, action: onSelectThisMac)
                .help("This Mac")
            RailButton(systemImage: "folder.badge.plus", isSelected: false, action: onAddProject)
                .help("Open project")
            Spacer()
            RailButton(systemImage: "gearshape", isSelected: false, action: onOpenSettings)
                .help("Settings")
        }
        .padding(.top, 54)
        .padding(.bottom, 16)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(.bar)
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
    let project: ProjectRecord
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SidebarNavigationRow(
            title: project.name,
            subtitle: project.path,
            systemImage: "folder",
            isSelected: isSelected,
            action: onSelect
        )
        .contextMenu {
            Button("Remove from Orbita", role: .destructive, action: onRemove)
        }
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
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor : .clear)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .animation(.snappy(duration: 0.16), value: isSelected)
    }
}

private struct RailButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                }
        }
        .buttonStyle(.plain)
    }
}
