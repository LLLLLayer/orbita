import SwiftUI
import UniformTypeIdentifiers
import OrbitaCore

struct ContentView: View {
    @StateObject private var store = ProjectCapabilityStore()
    @StateObject private var fullDiskAccess = FullDiskAccessGate()
    @AppStorage("customAgentsJSON") private var customAgentsJSON = "[]"
    @AppStorage("agentOrderJSON") private var agentOrderJSON = "[]"
    @AppStorage("hiddenAgentIDsJSON") private var hiddenAgentIDsJSON = "[]"
    @AppStorage("categoryOrderJSON") private var categoryOrderJSON = "[]"
    @AppStorage("hiddenCategoryIDsJSON") private var hiddenCategoryIDsJSON = "[]"
    @AppStorage("scanRefreshPolicy") private var scanRefreshPolicy = ScanRefreshPolicy.oneHour.rawValue
    @AppStorage("orbitaLanguageCode") private var orbitaLanguageCode = OrbitaLanguage.english.rawValue
    @AppStorage("capabilitySortOption") private var capabilitySortOption = CapabilitySortOption.nameAscending.rawValue
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
    @State private var markdownPreviewDocument: MarkdownPreviewDocument?
    @State private var pendingPlan: ApplyPlan?
    @State private var pendingSyncCapability: Capability?
    @State private var pendingScopedAction: PendingScopedCapabilityAction?
    @State private var importerPresented = false
    @State private var didPrepareStore = false
    @State private var didPreflightUserDirectoryAccess = false
    @State private var isPreflightingUserDirectoryAccess = false
    @State private var userDirectoryAccessMessage: String?

    var body: some View {
        Group {
            if canEnterApp {
                mainAppLayout
                    .transition(.opacity)
            } else {
                FullDiskAccessOnboardingView(
                    status: fullDiskAccess.status,
                    directoryAccessMessage: userDirectoryAccessMessage,
                    isPreflightingDirectoryAccess: isPreflightingUserDirectoryAccess,
                    onOpenSettings: {
                        fullDiskAccess.openSystemSettings()
                    },
                    onContinueWithoutAccess: {
                        preflightUserDirectoryAccess()
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
                markdownPreviewDocument = nil
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
        .sheet(item: $pendingSyncCapability) { capability in
            SyncCapabilitySheet(
                capability: capability,
                agents: agentOptions,
                visibleAgentIDs: visibleAgentIDs(for: capability),
                onSelect: { agent in
                    let plan = store.planSync(capability, to: agent)
                    pendingSyncCapability = nil
                    if let plan {
                        DispatchQueue.main.async {
                            if plan.requiresConfirmation {
                                pendingPlan = plan
                            } else {
                                apply(plan)
                            }
                        }
                    }
                },
                onCancel: {
                    pendingSyncCapability = nil
                }
            )
        }
        .sheet(item: $pendingScopedAction) { action in
            ScopedCapabilityActionSheet(
                title: action.title,
                message: action.message,
                currentButtonTitle: action.currentButtonTitle,
                allButtonTitle: action.allButtonTitle,
                currentUnavailableReason: action.currentUnavailableReason,
                isDestructive: action.kind == .delete,
                onCurrent: {
                    guard let currentPlan = action.currentPlan else { return }
                    pendingScopedAction = nil
                    apply(currentPlan)
                },
                onAll: {
                    pendingScopedAction = nil
                    apply(action.allPlan)
                },
                onCancel: {
                    pendingScopedAction = nil
                }
            )
        }
        .sheet(isPresented: $addingAgentPresented) {
            AddAgentSheet { agent in
                var agents = customAgents
                agents.append(agent)
                if saveCustomAgents(agents) {
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
            if let markdownPreviewDocument {
                MarkdownPreviewPage(document: markdownPreviewDocument) {
                    withAnimation(.snappy(duration: 0.22)) {
                        self.markdownPreviewDocument = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if settingsPresented {
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
                        graphForAgentVisibility: store.graph,
                        selectedCapability: $selectedCapability,
                        expandedGroupIDs: $expandedGroupIDs,
                        onAddAgent: {
                            addingAgentPresented = true
                        },
                        onMoveAgent: moveAgent,
                        onPinAgent: pinAgent,
                        onDeleteAgent: deleteAgent,
                        onMoveCategory: moveCategory,
                        onPinCategory: pinCategory,
                        onHideCategory: hideCategory,
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
                        },
                        onSyncCapability: { capability in
                            pendingSyncCapability = capability
                        }
                    )
                    .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)

                    if store.hasActiveContext, inspectorVisible {
                        Divider()
                            .transition(.opacity)
                        CapabilityInspectorView(
                            capability: selectedCapability,
                            selectedAgent: selectedAgent,
                            onClose: {
                                withAnimation(.snappy(duration: 0.22)) {
                                    inspectorVisible = false
                                    selectedCapability = nil
                                }
                            },
                            onEnable: { capability in
                                pendingPlan = store.planEnable(capability, visibleTo: selectedAgent)
                            },
                            onDisable: { capability in
                                pendingScopedAction = scopedCapabilityAction(kind: .disable, capability: capability)
                            },
                            onDelete: { capability in
                                pendingScopedAction = scopedCapabilityAction(kind: .delete, capability: capability)
                            },
                            onOpenMarkdownPreview: { document in
                                withAnimation(.snappy(duration: 0.22)) {
                                    markdownPreviewDocument = document
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
                    markdownPreviewDocument = nil
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
        markdownPreviewDocument = nil
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
        fullDiskAccess.status.isGranted || didPreflightUserDirectoryAccess
    }

    private func preflightUserDirectoryAccess() {
        guard !isPreflightingUserDirectoryAccess else { return }
        isPreflightingUserDirectoryAccess = true
        userDirectoryAccessMessage = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                UserDirectoryAccessPreflight.run()
            }.value

            isPreflightingUserDirectoryAccess = false
            if result.deniedURLs.isEmpty {
                didPreflightUserDirectoryAccess = true
                userDirectoryAccessMessage = nil
                prepareStoreIfPermitted()
            } else {
                didPreflightUserDirectoryAccess = false
                let path = result.deniedURLs.first?.abbreviatedPath ?? "a required folder"
                userDirectoryAccessMessage = "Orbita still cannot read \(path). Allow the macOS prompt, then try again or enable Full Disk Access."
            }
        }
    }

    private var filteredCapabilities: [Capability] {
        visibleCapabilities.filter { selectedGroup.matches($0) }
    }

    private var sortedCapabilities: [Capability] {
        filteredCapabilities.sorted(by: currentSortOption.comparator)
    }

    private var displayGroupingCapabilities: [Capability] {
        if selectedGroup == .plugin {
            return visibleCapabilities.sorted(by: currentSortOption.comparator)
        }
        return sortedCapabilities
    }

    private var visibleCapabilities: [Capability] {
        guard let graph = store.graph else { return [] }
        guard let selectedAgent else { return graph.capabilities }
        return selectedAgent.visibleCapabilities(in: graph)
    }

    private var capabilityDisplaySections: [CapabilityCollectionSection] {
        let items = CapabilityDisplayGrouper()
            .items(
                for: displayGroupingCapabilities,
                preservesInputOrder: true,
                groupsPluginChildren: selectedGroup == .all || selectedGroup == .plugin
            )
            .filter(displayItemMatchesSelectedGroup)
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

    private func displayItemMatchesSelectedGroup(_ item: CapabilityDisplayItem) -> Bool {
        switch selectedGroup {
        case .all:
            return true
        case .plugin:
            switch item {
            case let .capability(capability):
                return capability.type == .plugin
            case let .group(group):
                return group.kind == .plugin
            }
        default:
            switch item {
            case let .capability(capability):
                return selectedGroup.matches(capability)
            case let .group(group):
                return group.capabilities.contains { selectedGroup.matches($0) }
            }
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
        let hiddenIDs = hiddenAgentIDs
        let defaultAgents = AgentSelection.defaultAgents.filter { !hiddenIDs.contains($0.id) }
        return defaultAgents + customAgents
    }

    private var customAgents: [AgentSelection] {
        guard let data = customAgentsJSON.data(using: .utf8),
              let agents = try? JSONDecoder().decode([AgentSelection].self, from: data)
        else {
            return []
        }
        return agents
    }

    @discardableResult
    private func saveCustomAgents(_ agents: [AgentSelection]) -> Bool {
        if let data = try? JSONEncoder().encode(agents),
           let json = String(data: data, encoding: .utf8) {
            customAgentsJSON = json
            return true
        }
        return false
    }

    private var agentOrderIDs: [String] {
        guard let data = agentOrderJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return ids
    }

    private var hiddenAgentIDs: Set<String> {
        guard let data = hiddenAgentIDsJSON.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(ids).subtracting(deleteProtectedAgentIDs)
    }

    private var deleteProtectedAgentIDs: Set<String> {
        [AgentSelection.codex.id, AgentSelection.claudeCode.id]
    }

    private func saveHiddenAgentIDs(_ hiddenIDs: Set<String>) {
        let sanitizedIDs = hiddenIDs.subtracting(deleteProtectedAgentIDs)
        if let selectedAgent, sanitizedIDs.contains(selectedAgent.id) {
            self.selectedAgent = nil
        }
        if let data = try? JSONEncoder().encode(Array(sanitizedIDs).sorted()),
           let json = String(data: data, encoding: .utf8) {
            hiddenAgentIDsJSON = json
        }
    }

    private func saveAgentOrder(_ orderedAgents: [AgentSelection]) {
        saveAgentOrderIDs(orderedAgents.map(\.id))
    }

    private func saveAgentOrderIDs(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids),
           let json = String(data: data, encoding: .utf8) {
            agentOrderJSON = json
        }
    }

    private func pinAgent(id agentID: String) {
        var orderedAgents = agentOptions
        guard let sourceIndex = orderedAgents.firstIndex(where: { $0.id == agentID }),
              sourceIndex != orderedAgents.startIndex else {
            return
        }

        let agent = orderedAgents.remove(at: sourceIndex)
        orderedAgents.insert(agent, at: orderedAgents.startIndex)
        saveAgentOrder(orderedAgents)
    }

    private func deleteAgent(id agentID: String) {
        guard !deleteProtectedAgentIDs.contains(agentID) else {
            return
        }
        if AgentSelection.defaultAgents.contains(where: { $0.id == agentID }) {
            var hiddenIDs = hiddenAgentIDs
            hiddenIDs.insert(agentID)
            saveHiddenAgentIDs(hiddenIDs)
            saveAgentOrderIDs(agentOrderIDs.filter { $0 != agentID })
            return
        }

        let remainingAgents = customAgents.filter { $0.id != agentID }
        guard remainingAgents.count != customAgents.count else {
            return
        }

        if saveCustomAgents(remainingAgents) {
            if selectedAgent?.id == agentID {
                selectedAgent = nil
            }
            saveAgentOrderIDs(agentOrderIDs.filter { $0 != agentID })
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

    private func visibleAgentIDs(for capability: Capability) -> Set<String> {
        guard let graph = store.graph else {
            return []
        }
        let targetIDs = capabilityTargetIDs(for: capability)
        let targetCapabilities = graph.capabilities.filter { targetIDs.contains($0.id) }
        return Set(agentOptions.compactMap { agent in
            let isVisible = targetCapabilities.allSatisfy { agent.includesCapability($0, in: graph) }
            return isVisible ? agent.id : nil
        })
    }

    private func capabilityTargetIDs(for capability: Capability) -> Set<String> {
        let childIDs = capability.metadata["childIDs"]?
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty } ?? []
        return Set(childIDs.isEmpty ? [capability.id] : childIDs)
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

    private func pinCategory(id categoryID: String) {
        var orderedCategories = orderedCategoryOptions
        guard let sourceIndex = orderedCategories.firstIndex(where: { $0.rawValue == categoryID }),
              sourceIndex != orderedCategories.startIndex else {
            return
        }

        let category = orderedCategories.remove(at: sourceIndex)
        orderedCategories.insert(category, at: orderedCategories.startIndex)
        saveCategoryOrder(orderedCategories)
    }

    private func hideCategory(id categoryID: String) {
        guard categoryID != CapabilityCategory.all.rawValue else {
            return
        }
        var hiddenIDs = hiddenCategoryIDs
        hiddenIDs.insert(categoryID)
        saveHiddenCategories(hiddenIDs)
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

    private func scopedCapabilityAction(kind: PendingScopedCapabilityAction.Kind, capability: Capability) -> PendingScopedCapabilityAction? {
        let allPlan: ApplyPlan?
        let currentPlan: ApplyPlan?
        switch kind {
        case .delete:
            allPlan = store.planDelete(capability)
            currentPlan = selectedAgent.flatMap { store.planDelete(capability, visibleTo: $0) }
        case .disable:
            allPlan = store.planDisable(capability)
            currentPlan = selectedAgent.flatMap { store.planDisable(capability, visibleTo: $0) }
        }

        guard let allPlan else {
            return nil
        }

        let scopedPlan: ApplyPlan?
        if let currentPlan,
           !plansHaveSameEffect(currentPlan, allPlan) {
            scopedPlan = currentPlan
        } else {
            scopedPlan = nil
        }

        return PendingScopedCapabilityAction(
            kind: kind,
            name: capability.name,
            allPlan: allPlan,
            currentPlan: scopedPlan,
            currentAgentName: selectedAgent?.displayName
        )
    }

    private func affectedCapabilityIDs(in plan: ApplyPlan) -> Set<String> {
        Set(plan.affectedCapabilityIDs ?? [plan.capabilityID])
    }

    private func plansHaveSameEffect(_ lhs: ApplyPlan, _ rhs: ApplyPlan) -> Bool {
        affectedCapabilityIDs(in: lhs) == affectedCapabilityIDs(in: rhs)
            && operationEffectSignature(lhs) == operationEffectSignature(rhs)
    }

    private func operationEffectSignature(_ plan: ApplyPlan) -> Set<String> {
        Set(plan.operations
            .filter { $0.kind != .appendLog }
            .map { operation in
                [
                    operation.kind.rawValue,
                    operation.path,
                    operation.target ?? "",
                    operation.content ?? ""
                ].joined(separator: "\u{1F}")
            })
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

private struct PendingScopedCapabilityAction: Identifiable {
    enum Kind {
        case delete
        case disable
    }

    let kind: Kind
    let name: String
    let allPlan: ApplyPlan
    let currentPlan: ApplyPlan?
    let currentAgentName: String?

    var id: String {
        "\(kind):\(allPlan.id):\(currentPlan?.id ?? "all")"
    }

    var title: String {
        switch kind {
        case .delete:
            return "Delete \(name)?"
        case .disable:
            return "Disable \(name)?"
        }
    }

    var role: ButtonRole? {
        switch kind {
        case .delete:
            return .destructive
        case .disable:
            return nil
        }
    }

    var currentUnavailableReason: String? {
        guard currentPlan == nil else {
            return nil
        }
        let agentName = currentAgentName ?? "an individual Agent"
        switch kind {
        case .delete:
            return "This capability is already the root copy for \(agentName), or no single Agent scope is selected. Use all copies to remove the canonical source."
        case .disable:
            return "This capability is already the root copy for \(agentName), or no single Agent scope is selected. Use all copies to disable the canonical source."
        }
    }

    var currentButtonTitle: String {
        let agentName = currentAgentName ?? "Current Agent"
        switch kind {
        case .delete:
            return "Delete Only \(agentName)"
        case .disable:
            return "Disable Only \(agentName)"
        }
    }

    var allButtonTitle: String {
        switch kind {
        case .delete:
            return "Delete All Copies"
        case .disable:
            return "Disable All Copies"
        }
    }

    var message: String {
        switch kind {
        case .delete:
            return deleteMessage
        case .disable:
            return disableMessage
        }
    }

    private var deleteMessage: String {
        let count = affectedCount(in: allPlan)
        if currentPlan != nil, count > 1 {
            return "Choose whether to permanently remove only the current agent-visible source or all \(count) mirrored sources."
        }
        if count > 1 {
            return "This will permanently remove \(count) mirrored capability sources."
        }
        return "This will permanently remove the selected capability source."
    }

    private var disableMessage: String {
        let scopedText: String
        let count = affectedCount(in: allPlan)
        if currentPlan != nil, count > 1 {
            scopedText = "Choose whether to disable only the current agent-visible source or all \(count) mirrored sources."
        } else if count > 1 {
            scopedText = "This will disable all \(count) mirrored sources."
        } else {
            scopedText = "This will disable the selected capability source."
        }

        let operations = allPlan.operations
        let hasCache = operations.contains { $0.kind == .cachePath }
        let hasSymlinkRemoval = operations.contains { operation in
            operation.kind == .removePath && operation.description.localizedCaseInsensitiveContains("symbolic link")
        }
        if hasCache && hasSymlinkRemoval {
            return "\(scopedText) Symbolic links are removed as links only. Real files are copied to .orbita/cache/disabled and restored when enabled."
        }
        if hasCache {
            return "\(scopedText) Real files are copied to .orbita/cache/disabled and restored when enabled."
        }
        if hasSymlinkRemoval {
            return "\(scopedText) Symbolic links are removed as links only; their targets remain untouched."
        }
        return "\(scopedText) Orbita will record disabled intent in .agents."
    }

    private func affectedCount(in plan: ApplyPlan) -> Int {
        plan.affectedCapabilityIDs?.count ?? 1
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
