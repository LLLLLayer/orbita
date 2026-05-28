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
    @AppStorage("hideMacScopeInProject") private var hideMacScopeInProject = false
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
    @State private var toastMessage: String?
    @State private var toastToken = UUID()

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
        .overlay(alignment: .top) {
            if let toastMessage {
                OrbitaToast(message: toastMessage)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .tint(OrbitaTheme.prominentControlFill)
        .environment(\.locale, Locale(identifier: orbitaLanguageCode))
        .localized()
        .onAppear {
            LocalizationManager.shared.setLanguage(orbitaLanguageCode)
        }
        .onChange(of: orbitaLanguageCode) { _, newValue in
            LocalizationManager.shared.setLanguage(newValue)
        }
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
                agents: syncAgentOptions(for: capability),
                visibleAgentIDs: visibleAgentIDs(for: capability),
                onSelect: { request in
                    let plan = store.planSync(
                        capability,
                        to: request.agent,
                        mode: request.mode,
                        destinationScope: request.destinationScope
                    )
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
                primaryButtonTitle: action.primaryButtonTitle,
                secondaryConfirmationMessage: action.secondaryConfirmationMessage,
                isDestructive: action.kind == .delete,
                onConfirm: {
                    pendingScopedAction = nil
                    apply(action.plan)
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
                        graph: displayGraph,
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
                        hideMacScope: $hideMacScopeInProject,
                        showHideMacScopeToggle: store.hasProject,
                        selectedCapability: $selectedCapability,
                        expandedGroupIDs: $expandedGroupIDs,
                        onAddAgent: {
                            showComingSoonToast()
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
                            onBeginNativeMutation: { mutation, capability in
                                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.08)) {
                                    let token = store.beginOptimisticMutation(mutation, capability: capability)
                                    if mutation == .delete {
                                        selectedCapability = nil
                                    } else if let updatedCapability = store.capability(id: capability.id) {
                                        selectedCapability = updatedCapability
                                    }
                                    return token
                                }
                            },
                            onNativeMutationSucceeded: { mutation, capability, token in
                                store.finishOptimisticMutation(mutation, capability: capability, token: token)
                                if mutation == .delete {
                                    selectedCapability = nil
                                } else if let updatedCapability = store.capability(id: capability.id) {
                                    selectedCapability = updatedCapability
                                }
                            },
                            onNativeMutationFailed: { capability, token, message in
                                store.failOptimisticMutation(token, message: message)
                                if let restoredCapability = store.capability(id: capability.id) {
                                    selectedCapability = restoredCapability
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
                onPinProject: { project in
                    store.pinProject(project)
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

    private func showComingSoonToast() {
        let token = UUID()
        toastToken = token
        withAnimation(.snappy(duration: 0.18)) {
            toastMessage = "敬请期待"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard toastToken == token else { return }
            withAnimation(.snappy(duration: 0.18)) {
                toastMessage = nil
            }
        }
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
        guard let graph = displayGraph else { return [] }
        guard let selectedAgent else { return graph.capabilities }
        return selectedAgent.visibleCapabilities(in: graph)
    }

    private var displayGraph: CapabilityGraph? {
        guard let graph = store.graph else { return nil }
        guard hideMacScopeInProject, store.hasProject else { return graph }
        var filtered = graph
        filtered.capabilities = graph.capabilities.filter { $0.scope != .user && $0.scope != .installed }
        return filtered
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
            let sortedSectionItems = sectionItems.sorted(by: currentSortOption.itemComparator)
            if selectedGroup == .all {
                return CapabilityCollectionSection(
                    id: kind.rawValue,
                    title: kind.title,
                    subtitle: "\(sectionItems.count) items",
                    subsections: allTabSubsections(for: sortedSectionItems)
                )
            }
            return CapabilityCollectionSection(
                id: kind.rawValue,
                title: kind.title,
                subtitle: "\(sectionItems.count) items",
                items: sortedSectionItems
            )
        }
    }

    private func allTabSubsections(for items: [CapabilityDisplayItem]) -> [CapabilityCollectionSubsection] {
        let grouped = Dictionary(grouping: items, by: allTabSubsectionKind(for:))
        return allTabSubsectionOrder.compactMap { kind in
            guard let sectionItems = grouped[kind], !sectionItems.isEmpty else {
                return nil
            }
            return CapabilityCollectionSubsection(
                id: kind.id,
                title: kind.title,
                subtitle: "\(sectionItems.count) items",
                items: sectionItems
            )
        }
    }

    private var allTabSubsectionOrder: [AllTabSubsectionKind] {
        orderedCategoryOptions
            .filter { $0 != .all }
            .map(AllTabSubsectionKind.category) + [.other]
    }

    private func allTabSubsectionKind(for item: CapabilityDisplayItem) -> AllTabSubsectionKind {
        switch item {
        case let .group(group):
            return groupSubsectionKind(for: group)
        case let .capability(capability):
            return AllTabSubsectionKind(capabilityType: capability.type)
        }
    }

    private func groupSubsectionKind(for group: CapabilityGroup) -> AllTabSubsectionKind {
        if group.kind == .plugin {
            return .category(.plugin)
        }
        let kinds = Set(group.capabilities.map { AllTabSubsectionKind(capabilityType: $0.type) })
        guard kinds.count == 1, let kind = kinds.first else {
            return .category(.plugin)
        }
        return kind
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
                return groupSubsectionKind(for: group) == .category(.plugin)
            }
        default:
            switch item {
            case let .capability(capability):
                return selectedGroup.matches(capability)
            case let .group(group):
                return groupSubsectionKind(for: group) == .category(selectedGroup)
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

    private func syncAgentOptions(for capability: Capability) -> [AgentSelection] {
        guard let graph = store.graph else {
            return []
        }
        let targetIDs = capabilityTargetIDs(for: capability)
        let capabilities = graph.capabilities.filter {
            targetIDs.contains($0.id) && $0.type.supportsAgentSync
        }
        guard !capabilities.isEmpty else {
            return []
        }

        return agentOptions.filter { agent in
            guard let agentID = agent.skillsInstallAgentID else {
                return false
            }
            return capabilities.allSatisfy { syncCapability($0, isCompatibleWith: agentID) }
        }
    }

    private func syncCapability(_ capability: Capability, isCompatibleWith agentID: String) -> Bool {
        switch capability.type {
        case .skill:
            return true
        case .command:
            let ext = URL(fileURLWithPath: capability.metadata["sourcePath"] ?? capability.source.path).pathExtension.lowercased()
            if agentID == "claude-code" {
                return ext == "md"
            }
            if agentID == "codex" {
                return ["md", "json", "toml"].contains(ext)
            }
            return false
        case .agent:
            let ext = URL(fileURLWithPath: capability.metadata["sourcePath"] ?? capability.source.path).pathExtension.lowercased()
            if agentID == "claude-code" {
                return ext == "md"
            }
            if agentID == "codex" {
                return ["md", "json", "toml"].contains(ext)
            }
            return false
        case .plugin, .mcpServer, .rule, .instruction, .hook, .unknown:
            return false
        }
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
        [.all, .plugin, .skill, .command, .agent, .hook, .mcp]
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
        let plan: ApplyPlan?
        switch kind {
        case .delete:
            plan = selectedAgent.flatMap { store.planDelete(capability, visibleTo: $0) }
                ?? store.planDelete(capability)
        case .disable:
            plan = selectedAgent.flatMap { store.planDisable(capability, visibleTo: $0) }
                ?? store.planDisable(capability)
        }

        guard let plan else {
            return nil
        }

        return PendingScopedCapabilityAction(
            kind: kind,
            name: capability.name,
            plan: plan,
            currentAgentName: selectedAgent?.displayName,
            linkedSymlinkAgentNames: kind == .delete
                ? linkedSymlinkAgentNamesToSelectedCanonical(for: capability)
                : []
        )
    }

    private func linkedSymlinkAgentNamesToSelectedCanonical(for capability: Capability) -> [String] {
        guard let selectedAgentID = selectedAgent?.skillsInstallAgentID,
              let graph = store.graph
        else {
            return []
        }

        let targetIDs = capabilityTargetIDs(for: capability)
        let targetCapabilities = graph.capabilities.filter { targetIDs.contains($0.id) }
        let names = targetCapabilities.flatMap { capability in
            let targets = skillInstallTargets(in: capability)
            guard targets.first(where: { $0.agentID == selectedAgentID })?.relationship == "canonical" else {
                return [String]()
            }
            return targets
                .filter { $0.agentID != selectedAgentID && $0.relationship == "symlink" }
                .map { agentDisplayName(forSkillInstallAgentID: $0.agentID) }
        }
        return uniquePreservingOrder(names)
    }

    private func skillInstallTargets(in capability: Capability) -> [SkillInstallTargetSummary] {
        guard capability.type == .skill,
              let value = capability.metadata["skillsInstallTargets"]
        else {
            return []
        }

        return value.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let assignment = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard assignment.count == 2 else {
                return nil
            }
            let relationshipAndPath = assignment[1].split(separator: ":", maxSplits: 1).map(String.init)
            guard relationshipAndPath.count == 2, !relationshipAndPath[1].isEmpty else {
                return nil
            }
            return SkillInstallTargetSummary(
                agentID: assignment[0],
                relationship: relationshipAndPath[0]
            )
        }
    }

    private func agentDisplayName(forSkillInstallAgentID agentID: String) -> String {
        if let agent = agentOptions.first(where: { $0.skillsInstallAgentID == agentID }) {
            return agent.displayName
        }
        if let agent = SkillsAgentCatalog.agents.first(where: { $0.id == agentID }) {
            return agent.displayName
        }
        return agentID
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private var currentSortOption: CapabilitySortOption {
        CapabilitySortOption(rawValue: capabilitySortOption) ?? .nameAscending
    }
}

private struct OrbitaToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(OrbitaTheme.border)
        }
        .shadow(color: OrbitaTheme.cardShadow, radius: 12, x: 0, y: 6)
        .accessibilityLabel(message)
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

private enum AllTabSubsectionKind: Hashable {
    case category(CapabilityCategory)
    case other

    init(capabilityType: CapabilityType) {
        switch capabilityType {
        case .plugin:
            self = .category(.plugin)
        case .skill:
            self = .category(.skill)
        case .agent:
            self = .category(.agent)
        case .command:
            self = .category(.command)
        case .mcpServer:
            self = .category(.mcp)
        case .hook:
            self = .category(.hook)
        case .instruction, .rule:
            self = .other
        case .unknown:
            self = .other
        }
    }

    var id: String {
        switch self {
        case let .category(category):
            return category.rawValue
        case .other:
            return "other"
        }
    }

    var title: String {
        switch self {
        case let .category(category):
            return category.title
        case .other:
            return "Other"
        }
    }
}

private struct SkillInstallTargetSummary {
    var agentID: String
    var relationship: String
}

private struct PendingScopedCapabilityAction: Identifiable {
    enum Kind {
        case delete
        case disable
    }

    let kind: Kind
    let name: String
    let plan: ApplyPlan
    let currentAgentName: String?
    let linkedSymlinkAgentNames: [String]

    var id: String {
        "\(kind):\(plan.id)"
    }

    var title: String {
        switch kind {
        case .delete:
            return "Delete \(name)?"
        case .disable:
            return "Disable \(name)?"
        }
    }

    var primaryButtonTitle: String {
        switch kind {
        case .delete:
            return "Delete Current"
        case .disable:
            return "Disable Current"
        }
    }

    var secondaryConfirmationMessage: String? {
        guard kind == .delete, !linkedSymlinkAgentNames.isEmpty else {
            return nil
        }
        return "This will also delete linked symlinks for \(linkedAgentList). Confirm delete?"
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
        let agentText = currentAgentName.map { " for \($0)" } ?? ""
        if !linkedSymlinkAgentNames.isEmpty {
            return "This will permanently delete the current capability source\(agentText). \(linkedAgentList) are symlinks to this source and will be deleted together to avoid broken links."
        }
        let count = affectedCount(in: plan)
        if count > 1 {
            return "This will permanently delete the current selection\(agentText), including \(count) grouped capability sources."
        }
        return "This will permanently delete the current capability source\(agentText)."
    }

    private var disableMessage: String {
        let scopedText: String
        let count = affectedCount(in: plan)
        let agentText = currentAgentName.map { " for \($0)" } ?? ""
        if count > 1 {
            scopedText = "This will disable the current selection\(agentText), including \(count) grouped capability sources."
        } else {
            scopedText = "This will disable the current capability source\(agentText)."
        }

        let operations = plan.operations
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

    private var linkedAgentList: String {
        linkedSymlinkAgentNames.joined(separator: ", ")
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
