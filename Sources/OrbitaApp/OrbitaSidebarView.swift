import SwiftUI
import OrbitaCore

enum OrbitaLayoutMetrics {
    static let sidebarWidth: CGFloat = 224
    static let sidebarRailWidth: CGFloat = 64
    static let inspectorWidth: CGFloat = 340
    static let minimumWindowWidth: CGFloat = 1100
    static let minimumWindowHeight: CGFloat = 720
}

struct OrbitaSidebarView: View {
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

    @State private var draggingProjectPath: String?
    @State private var projectRowFrames: [String: CGRect] = [:]

    private let projectListCoordinateSpace = "orbita.project-sidebar.projects"

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
                                        isDragging: draggingProjectPath == project.path,
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
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: ProjectRowFramePreferenceKey.self,
                                                value: [project.path: proxy.frame(in: .named(projectListCoordinateSpace))]
                                            )
                                        }
                                    }
                                    .simultaneousGesture(projectReorderGesture(for: project))
                                    .help("Long press and drag to reorder")
                                }
                            }
                            .coordinateSpace(name: projectListCoordinateSpace)
                            .onPreferenceChange(ProjectRowFramePreferenceKey.self) { frames in
                                projectRowFrames = frames
                            }
                        }
                    }
                )
            }

            Spacer(minLength: 16)

            SidebarSettingsRow(
                title: "Settings",
                subtitle: "Preferences",
                systemImage: "gearshape",
                action: onOpenSettings
            )
            .padding(.bottom, 16)
        }
        .frame(width: OrbitaLayoutMetrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(OrbitaTheme.sidebarBackground)
    }

    private func projectReorderGesture(for project: ProjectRecord) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(projectListCoordinateSpace)))
            .onChanged { value in
                switch value {
                case .first(true):
                    if draggingProjectPath == nil {
                        draggingProjectPath = project.path
                    }
                case .second(true, let drag):
                    if draggingProjectPath == nil {
                        draggingProjectPath = project.path
                    }
                    guard let drag else { return }
                    moveProject(project.path, to: drag.location)
                default:
                    break
                }
            }
            .onEnded { _ in
                draggingProjectPath = nil
            }
    }

    private func moveProject(_ projectPath: String, to location: CGPoint) {
        guard let fromIndex = projects.firstIndex(where: { $0.path == projectPath }),
              let targetPath = targetProjectPath(at: location),
              targetPath != projectPath,
              let toIndex = projects.firstIndex(where: { $0.path == targetPath })
        else {
            return
        }

        withAnimation(.snappy(duration: 0.16)) {
            onMoveProjects(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    private func targetProjectPath(at location: CGPoint) -> String? {
        let orderedFrames = projects.compactMap { project -> (path: String, frame: CGRect)? in
            guard let frame = projectRowFrames[project.path] else { return nil }
            return (project.path, frame)
        }
        guard let first = orderedFrames.first,
              let last = orderedFrames.last
        else {
            return nil
        }
        if location.y <= first.frame.minY {
            return first.path
        }
        if location.y >= last.frame.maxY {
            return last.path
        }
        if let containing = orderedFrames.first(where: { location.y >= $0.frame.minY && location.y <= $0.frame.maxY }) {
            return containing.path
        }
        return orderedFrames.min {
            abs($0.frame.midY - location.y) < abs($1.frame.midY - location.y)
        }?.path
    }
}

struct OrbitaSidebarRail: View {
    let selection: String?
    let onExpand: () -> Void
    let onSelectThisMac: () -> Void
    let onAddProject: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RailButton(systemImage: "sidebar.left", isSelected: false, action: onExpand)
                    .help("Expand sidebar")
            }
            .frame(height: 86, alignment: .bottom)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                RailButton(systemImage: "desktopcomputer", isSelected: selection == ProjectCapabilityStore.environmentSelectionID, action: onSelectThisMac)
                    .help("This Mac")
                RailButton(systemImage: "folder.badge.plus", isSelected: false, action: onAddProject)
                    .help("Open project")
                Spacer(minLength: 12)
                RailButton(systemImage: "gearshape", isSelected: false, action: onOpenSettings)
                    .help("Settings")
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(width: OrbitaLayoutMetrics.sidebarRailWidth)
        .frame(maxHeight: .infinity)
        .background(OrbitaTheme.sidebarBackground)
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
    let isDragging: Bool
    let canPin: Bool
    let onSelect: () -> Void
    let onPin: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SidebarNavigationRow(
            title: project.name,
            subtitle: project.path,
            systemImage: "folder",
            isSelected: isSelected,
            action: onSelect
        )
        .opacity(isDragging ? 0.68 : 1)
        .scaleEffect(isDragging ? 0.985 : 1, anchor: .center)
        .contextMenu {
            Button(action: onPin) {
                Label("Pin to Top", systemImage: "pin")
            }
            .disabled(!canPin)
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("Delete", systemImage: "trash")
            }
        }
        .animation(.snappy(duration: 0.16), value: isDragging)
    }
}

private struct ProjectRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
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
    }
}
