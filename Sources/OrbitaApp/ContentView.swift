import SwiftUI
import UniformTypeIdentifiers
import OrbitaCore

struct ContentView: View {
    @StateObject private var store = ProjectCapabilityStore()
    @StateObject private var fullDiskAccess = FullDiskAccessGate()
    @AppStorage("customAgentsJSON") private var customAgentsJSON = "[]"
    @AppStorage("agentOrderJSON") private var agentOrderJSON = "[]"
    @AppStorage("categoryOrderJSON") private var categoryOrderJSON = "[]"
    @AppStorage("hiddenCategoryIDsJSON") private var hiddenCategoryIDsJSON = "[]"
    @AppStorage("scanRefreshPolicy") private var scanRefreshPolicy = ScanRefreshPolicy.oneHour.rawValue
    @AppStorage("orbitaLanguageCode") private var orbitaLanguageCode = OrbitaLanguage.english.rawValue
    @AppStorage("capabilitySortOption") private var capabilitySortOption = CapabilitySortOption.nameAscending.rawValue
    @AppStorage("fullDiskAccessOnboardingDismissed") private var fullDiskAccessOnboardingDismissed = false
    @State private var selectedProject: String? = ProjectCapabilityStore.environmentSelectionID
    @State private var selectedAgent: AgentSelection?
    @State private var selectedGroup = CapabilityCategory.all
    @State private var selectedCapability: Capability?
    @State private var expandedGroupIDs: Set<String> = []
    @State private var sidebarCollapsed = false
    @State private var inspectorVisible = true
    @State private var addingAgentPresented = false
    @State private var hidingCategoriesPresented = false
    @State private var settingsPresented = false
    @State private var pendingPlan: ApplyPlan?
    @State private var pendingDeletePlan: PendingDeletePlan?
    @State private var importerPresented = false
    @State private var didPrepareStore = false

    var body: some View {
        Group {
            if canEnterApp {
                mainAppLayout
                    .transition(.opacity)
            } else {
                FullDiskAccessOnboardingView(
                    status: fullDiskAccess.status,
                    onOpenSettings: {
                        fullDiskAccess.openSystemSettings()
                    },
                    onContinueWithoutAccess: {
                        fullDiskAccessOnboardingDismissed = true
                        prepareStoreIfPermitted()
                    }
                )
                .transition(.opacity)
            }
        }
        .frame(
            minWidth: OrbitaLayoutMetrics.minimumWindowWidth,
            minHeight: OrbitaLayoutMetrics.minimumWindowHeight
        )
        .background(OrbitaTheme.canvas)
        .background(OrbitaWindowChrome().frame(width: 0, height: 0))
        .ignoresSafeArea(.container, edges: .top)
        .tint(OrbitaTheme.prominentControlFill)
        .environment(\.locale, Locale(identifier: orbitaLanguageCode))
        .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                store.openProject(url)
                selectedProject = url.standardizedFileURL.resolvingSymlinksInPath().path
                selectedCapability = nil
                expandedGroupIDs.removeAll()
            }
        }
        .sheet(item: $pendingPlan) { plan in
            ApplyPlanSheet(plan: plan) {
                pendingPlan = nil
            } onApply: {
                apply(plan)
                pendingPlan = nil
            }
        }
        .alert(
            pendingDeletePlan.map { "Delete \($0.name)?" } ?? "Delete capability?",
            isPresented: Binding(
                get: { pendingDeletePlan != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletePlan = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeletePlan = nil
            }
            Button("Delete", role: .destructive) {
                if let plan = pendingDeletePlan?.plan {
                    apply(plan)
                } else if let pendingDeletePlan,
                          let command = pendingDeletePlan.nativeCommand {
                    runNativeDelete(command: command, workingDirectory: pendingDeletePlan.workingDirectory)
                }
                pendingDeletePlan = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(isPresented: $addingAgentPresented) {
            AddAgentSheet { agent in
                var agents = customAgents
                agents.append(agent)
                if let data = try? JSONEncoder().encode(agents),
                   let json = String(data: data, encoding: .utf8) {
                    customAgentsJSON = json
                    selectedAgent = agent
                }
                addingAgentPresented = false
            } onCancel: {
                addingAgentPresented = false
            }
        }
        .sheet(isPresented: $hidingCategoriesPresented) {
            HideCategoriesSheet(
                categories: orderedCategoryOptions,
                hiddenCategoryIDs: hiddenCategoryIDs,
                onSave: { hiddenIDs in
                    saveHiddenCategories(hiddenIDs)
                    hidingCategoriesPresented = false
                },
                onCancel: {
                    hidingCategoriesPresented = false
                }
            )
        }
        .onAppear {
            store.configure(refreshPolicy: scanRefreshPolicy)
            fullDiskAccess.refresh()
            prepareStoreIfPermitted()
        }
        .onChange(of: fullDiskAccess.status) { _, _ in
            prepareStoreIfPermitted()
        }
        .onChange(of: store.graph?.capabilities) { _, capabilities in
            guard let capabilities else {
                return
            }
            if let selectedCapability,
               let updatedCapability = capabilities.first(where: { $0.id == selectedCapability.id }) {
                self.selectedCapability = updatedCapability
                return
            }
            selectedCapability = capabilities.first
        }
        .onChange(of: selectedCapability) { _, capability in
            if capability != nil {
                inspectorVisible = true
            }
        }
        .onChange(of: selectedGroup) { _, _ in
            expandedGroupIDs.removeAll()
        }
        .onChange(of: selectedAgent) { _, _ in
            expandedGroupIDs.removeAll()
        }
        .onChange(of: scanRefreshPolicy) { _, value in
            store.configure(refreshPolicy: value)
        }
    }

    private var mainAppLayout: some View {
        Group {
            if settingsPresented {
                settingsView
            } else {
                HStack(spacing: 0) {
                    sidebar

                    Divider()

                    CapabilityMainView(
                        projectName: store.projectName,
                        hasActiveContext: store.hasActiveContext,
                        graph: store.graph,
                        isScanning: store.isScanning,
                        scanMessage: store.scanMessage,
                        scanProgress: store.scanProgress,
                        lastRefreshLabel: store.lastRefreshLabel,
                        errorMessage: store.errorMessage,
                        selectedAgent: $selectedAgent,
                        selectedGroup: $selectedGroup,
                        agentOptions: agentOptions,
                        categoryOptions: categoryOptions,
                        displaySections: capabilityDisplaySections,
                        selectedCapability: $selectedCapability,
                        expandedGroupIDs: $expandedGroupIDs,
                        onAddAgent: {
                            addingAgentPresented = true
                        },
                        onMoveAgent: moveAgent,
                        onMoveCategory: moveCategory,
                        onHideCategories: {
                            hidingCategoriesPresented = true
                        },
                        onOpenProject: {
                            importerPresented = true
                        },
                        onRefresh: {
                            store.reload(force: true)
                        },
                        onMerge: {
                            pendingPlan = store.planMerge()
                        },
                        onClean: {
                            pendingPlan = store.planClean()
                        }
                    )
                    .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

                    if store.hasActiveContext, inspectorVisible {
                        Divider()
                            .transition(.opacity)
                        CapabilityInspectorView(
                            capability: selectedCapability,
                            onClose: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    inspectorVisible = false
                                    selectedCapability = nil
                                }
                            },
                            onEnable: { capability in
                                pendingPlan = store.planEnable(capability)
                            },
                            onDisable: { capability in
                                pendingPlan = store.planDisable(capability)
                            },
                            onDelete: { capability in
                                if let command = capability.metadata["deleteCommand"],
                                   ["codex", "agents-skills"].contains(capability.metadata["manager"] ?? "") {
                                    pendingDeletePlan = PendingDeletePlan(
                                        name: capability.name,
                                        nativeCommand: command,
                                        workingDirectory: FileManager.default.currentDirectoryPath
                                    )
                                } else if let plan = store.planDelete(capability) {
                                    pendingDeletePlan = PendingDeletePlan(plan: plan, name: capability.name)
                                }
                            },
                            onNativePluginChanged: {
                                store.reload(force: true)
                            }
                        )
                        .frame(width: OrbitaLayoutMetrics.inspectorWidth)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private var settingsView: some View {
        OrbitaSettingsView(
            refreshPolicy: $scanRefreshPolicy,
            languageCode: $orbitaLanguageCode,
            sortOption: $capabilitySortOption,
            projectName: store.projectName,
            projectRootPath: store.activeRootPath,
            onRefresh: {
                store.reload(force: true)
            },
            onClose: {
                settingsPresented = false
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    @ViewBuilder
    private var sidebar: some View {
        if sidebarCollapsed {
            OrbitaSidebarRail(
                selection: selectedProject,
                onExpand: {
                    withAnimation(.snappy(duration: 0.22)) {
                        sidebarCollapsed = false
                    }
                },
                onSelectThisMac: {
                    selectEnvironment()
                },
                onAddProject: {
                    importerPresented = true
                },
                onOpenSettings: {
                    settingsPresented = true
                }
            )
            .frame(width: OrbitaLayoutMetrics.sidebarRailWidth)
            .transition(.move(edge: .leading).combined(with: .opacity))
        } else {
            OrbitaSidebarView(
                projects: store.projects,
                selection: $selectedProject,
                onCollapse: {
                    withAnimation(.snappy(duration: 0.22)) {
                        sidebarCollapsed = true
                    }
                },
                onAddProject: {
                    importerPresented = true
                },
                onSelectThisMac: {
                    selectEnvironment()
                },
                onSelectProject: { project in
                    selectedProject = project.path
                    selectedCapability = nil
                    expandedGroupIDs.removeAll()
                    store.openProject(URL(fileURLWithPath: project.path))
                },
                onRemoveProject: { project in
                    store.removeProject(project)
                    if selectedProject == project.path {
                        selectEnvironment()
                    }
                },
                onMoveProjects: { source, destination in
                    store.moveProjects(from: source, to: destination)
                },
                onOpenSettings: {
                    settingsPresented = true
                }
            )
            .frame(width: OrbitaLayoutMetrics.sidebarWidth)
            .clipped()
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private func selectEnvironment() {
        selectedProject = ProjectCapabilityStore.environmentSelectionID
        selectedCapability = nil
        expandedGroupIDs.removeAll()
        store.openEnvironment()
    }

    private func prepareStoreIfPermitted() {
        guard canEnterApp, !didPrepareStore else {
            return
        }
        didPrepareStore = true
        store.prepare()
        selectedProject = store.selectionID
    }

    private var canEnterApp: Bool {
        fullDiskAccess.status.isGranted || fullDiskAccessOnboardingDismissed
    }

    private var filteredCapabilities: [Capability] {
        visibleCapabilities.filter { selectedGroup.matches($0) }
    }

    private var sortedCapabilities: [Capability] {
        filteredCapabilities.sorted(by: currentSortOption.comparator)
    }

    private var visibleCapabilities: [Capability] {
        guard let graph = store.graph else { return [] }
        guard let selectedAgent else { return graph.capabilities }
        return selectedAgent.visibleCapabilities(in: graph)
    }

    private var capabilityDisplaySections: [CapabilityCollectionSection] {
        let items = CapabilityDisplayGrouper().items(for: sortedCapabilities, preservesInputOrder: true)
        let grouped = Dictionary(grouping: items, by: CapabilitySectionKind.init(item:))
        return CapabilitySectionKind.allCases.compactMap { kind in
            guard let sectionItems = grouped[kind], !sectionItems.isEmpty else {
                return nil
            }
            return CapabilityCollectionSection(
                id: kind.rawValue,
                title: kind.title,
                subtitle: "\(sectionItems.count) items",
                items: sectionItems.sorted(by: currentSortOption.itemComparator)
            )
        }
    }

    private var agentOptions: [AgentSelection] {
        let defaultOptions = defaultAgentOptions
        let orderIDs = agentOrderIDs
        guard !orderIDs.isEmpty else {
            return defaultOptions
        }

        let orderRank = Dictionary(uniqueKeysWithValues: orderIDs.enumerated().map { ($0.element, $0.offset) })
        return defaultOptions.enumerated().sorted { lhs, rhs in
            let lhsRank = orderRank[lhs.element.id] ?? Int.max
            let rhsRank = orderRank[rhs.element.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private var defaultAgentOptions: [AgentSelection] {
        AgentSelection.defaultAgents + customAgents
    }

    private var customAgents: [AgentSelection] {
        guard let data = customAgentsJSON.data(using: .utf8),
              let agents = try? JSONDecoder().decode([AgentSelection].self, from: data)
        else {
            return []
        }
        return agents
    }

    private var agentOrderIDs: [String] {
        guard let data = agentOrderJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return ids
    }

    private func saveAgentOrder(_ orderedAgents: [AgentSelection]) {
        let ids = orderedAgents.map(\.id)
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            agentOrderJSON = json
        }
    }

    private func moveAgent(id sourceID: String, to targetID: String) {
        guard sourceID != targetID else {
            return
        }
        var orderedAgents = agentOptions
        guard let sourceIndex = orderedAgents.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = orderedAgents.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let agent = orderedAgents.remove(at: sourceIndex)
        let updatedTargetIndex = orderedAgents.firstIndex { $0.id == targetID } ?? orderedAgents.endIndex
        let insertionIndex = sourceIndex < targetIndex
            ? min(updatedTargetIndex + 1, orderedAgents.endIndex)
            : updatedTargetIndex
        orderedAgents.insert(agent, at: insertionIndex)
        saveAgentOrder(orderedAgents)
    }

    private var categoryOptions: [CapabilityCategory] {
        let hiddenIDs = hiddenCategoryIDs
        return orderedCategoryOptions.filter { category in
            category == .all || !hiddenIDs.contains(category.rawValue)
        }
    }

    private var orderedCategoryOptions: [CapabilityCategory] {
        let defaultOptions = defaultCategoryOptions
        let orderIDs = categoryOrderIDs
        guard !orderIDs.isEmpty else {
            return defaultOptions
        }

        let orderRank = Dictionary(uniqueKeysWithValues: orderIDs.enumerated().map { ($0.element, $0.offset) })
        return defaultOptions.enumerated().sorted { lhs, rhs in
            let lhsRank = orderRank[lhs.element.rawValue] ?? Int.max
            let rhsRank = orderRank[rhs.element.rawValue] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private var defaultCategoryOptions: [CapabilityCategory] {
        CapabilityCategory.allCases
    }

    private var categoryOrderIDs: [String] {
        guard let data = categoryOrderJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return ids
    }

    private var hiddenCategoryIDs: Set<String> {
        guard let data = hiddenCategoryIDsJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(ids).subtracting([CapabilityCategory.all.rawValue])
    }

    private func saveCategoryOrder(_ orderedCategories: [CapabilityCategory]) {
        let ids = orderedCategories.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            categoryOrderJSON = json
        }
    }

    private func moveCategory(id sourceID: String, to targetID: String) {
        guard sourceID != targetID else {
            return
        }
        var orderedCategories = orderedCategoryOptions
        guard let sourceIndex = orderedCategories.firstIndex(where: { $0.rawValue == sourceID }),
              let targetIndex = orderedCategories.firstIndex(where: { $0.rawValue == targetID }) else {
            return
        }

        let category = orderedCategories.remove(at: sourceIndex)
        let updatedTargetIndex = orderedCategories.firstIndex { $0.rawValue == targetID } ?? orderedCategories.endIndex
        let insertionIndex = sourceIndex < targetIndex
            ? min(updatedTargetIndex + 1, orderedCategories.endIndex)
            : updatedTargetIndex
        orderedCategories.insert(category, at: insertionIndex)
        saveCategoryOrder(orderedCategories)
    }

    private func saveHiddenCategories(_ hiddenIDs: Set<String>) {
        let sanitizedIDs = hiddenIDs.subtracting([CapabilityCategory.all.rawValue])
        if sanitizedIDs.contains(selectedGroup.rawValue) {
            selectedGroup = .all
        }
        if let data = try? JSONEncoder().encode(Array(sanitizedIDs).sorted()),
           let json = String(data: data, encoding: .utf8) {
            hiddenCategoryIDsJSON = json
        }
    }

    private func apply(_ plan: ApplyPlan) {
        var didApply = false
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)) {
            didApply = store.apply(plan)
        }
        guard didApply else {
            return
        }
        if plan.action == .delete {
            selectedCapability = nil
        } else if let updatedCapability = store.capability(id: plan.capabilityID) {
            selectedCapability = updatedCapability
        }
    }

    private func runNativeDelete(command: String, workingDirectory: String) {
        Task.detached {
            let result = ShellCommandRunner.run(command, workingDirectory: workingDirectory)
            await MainActor.run {
                if result.exitCode == 0 {
                    selectedCapability = nil
                    store.reload(force: true)
                } else {
                    let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.errorMessage = output.isEmpty ? "Delete command failed: \(command)" : output
                }
            }
        }
    }

    private var deleteConfirmationMessage: String {
        guard let pendingDeletePlan else {
            return "This will permanently delete the selected capability source."
        }
        if pendingDeletePlan.nativeCommand != nil {
            return "This will run the native manager remove command for this capability."
        }
        let affectedCount = pendingDeletePlan.plan?.affectedCapabilityIDs?.count ?? 1
        if affectedCount > 1 {
            return "This will permanently delete \(affectedCount) capability sources in this virtual plugin."
        }
        return "This will permanently delete this capability source."
    }

    private var currentSortOption: CapabilitySortOption {
        CapabilitySortOption(rawValue: capabilitySortOption) ?? .nameAscending
    }
}

private enum CapabilitySectionKind: String, CaseIterable {
    case enabled
    case disabled

    init(item: CapabilityDisplayItem) {
        let capability = item.inspectionCapability
        if capability.statuses.contains(.disabled) {
            self = .disabled
        } else {
            self = .enabled
        }
    }

    var title: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .disabled:
            return "Disabled"
        }
    }
}

private struct PendingDeletePlan: Identifiable {
    let name: String
    let plan: ApplyPlan?
    let nativeCommand: String?
    let workingDirectory: String

    var id: String {
        plan?.id ?? nativeCommand ?? name
    }

    init(plan: ApplyPlan, name: String) {
        self.name = name
        self.plan = plan
        self.nativeCommand = nil
        self.workingDirectory = FileManager.default.currentDirectoryPath
    }

    init(name: String, nativeCommand: String, workingDirectory: String) {
        self.name = name
        self.plan = nil
        self.nativeCommand = nativeCommand
        self.workingDirectory = workingDirectory
    }
}

private extension CapabilitySortOption {
    var comparator: (Capability, Capability) -> Bool {
        { lhs, rhs in
            switch self {
            case .nameAscending:
                return compareByName(lhs, rhs)
            case .modifiedNewest:
                let lhsDate = modifiedAt(lhs)
                let rhsDate = modifiedAt(rhs)
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return compareByName(lhs, rhs)
            case .modifiedOldest:
                let lhsDate = modifiedAt(lhs)
                let rhsDate = modifiedAt(rhs)
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return compareByName(lhs, rhs)
            }
        }
    }

    var itemComparator: (CapabilityDisplayItem, CapabilityDisplayItem) -> Bool {
        { lhs, rhs in
            comparator(lhs.inspectionCapability, rhs.inspectionCapability)
        }
    }

    private func compareByName(_ lhs: Capability, _ rhs: Capability) -> Bool {
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison == .orderedSame {
            return lhs.id < rhs.id
        }
        return comparison == .orderedAscending
    }

    private func modifiedAt(_ capability: Capability) -> Date {
        guard let value = capability.metadata["modifiedAt"],
              let date = ISO8601DateFormatter().date(from: value) else {
            return .distantPast
        }
        return date
    }
}
