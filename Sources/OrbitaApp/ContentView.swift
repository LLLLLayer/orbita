import SwiftUI
import UniformTypeIdentifiers
import OrbitaCore

struct ContentView: View {
    @StateObject private var store = ProjectCapabilityStore()
    @StateObject private var fullDiskAccess = FullDiskAccessGate()
    @AppStorage("customAgentsJSON") private var customAgentsJSON = "[]"
    @AppStorage("scanRefreshPolicy") private var scanRefreshPolicy = ScanRefreshPolicy.oneHour.rawValue
    @AppStorage("orbitaLanguageCode") private var orbitaLanguageCode = OrbitaLanguage.english.rawValue
    @AppStorage("fullDiskAccessOnboardingDismissed") private var fullDiskAccessOnboardingDismissed = false
    @State private var selectedProject: String? = ProjectCapabilityStore.environmentSelectionID
    @State private var selectedAgent: AgentSelection?
    @State private var selectedGroup = CapabilityCategory.all
    @State private var selectedCapability: Capability?
    @State private var expandedGroupIDs: Set<String> = []
    @State private var sidebarCollapsed = false
    @State private var inspectorVisible = true
    @State private var addingAgentPresented = false
    @State private var settingsPresented = false
    @State private var pendingPlan: ApplyPlan?
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
        .frame(minWidth: 1100, minHeight: 720)
        .background(.regularMaterial)
        .background(OrbitaWindowChrome().frame(width: 0, height: 0))
        .ignoresSafeArea(.container, edges: .top)
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
                store.apply(plan)
                pendingPlan = nil
                selectedCapability = nil
            }
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
        .sheet(isPresented: $settingsPresented) {
            OrbitaSettingsView(
                refreshPolicy: $scanRefreshPolicy,
                languageCode: $orbitaLanguageCode
            ) {
                settingsPresented = false
            }
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
               capabilities.contains(where: { $0.id == selectedCapability.id }) {
                return
            }
            selectedCapability = capabilities.first
        }
        .onChange(of: selectedCapability) { _, capability in
            if capability != nil {
                withAnimation(.snappy(duration: 0.22)) {
                    inspectorVisible = true
                }
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
                displayItems: capabilityDisplayItems,
                selectedCapability: $selectedCapability,
                expandedGroupIDs: $expandedGroupIDs,
                onAddAgent: {
                    addingAgentPresented = true
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
                        pendingPlan = store.planDelete(capability)
                    }
                )
                .frame(width: 340)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
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
            .frame(width: 64)
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
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedProject = project.path
                        selectedCapability = nil
                        expandedGroupIDs.removeAll()
                    }
                    store.openProject(URL(fileURLWithPath: project.path))
                },
                onRemoveProject: { project in
                    store.removeProject(project)
                    if selectedProject == project.path {
                        selectEnvironment()
                    }
                },
                onOpenSettings: {
                    settingsPresented = true
                }
            )
            .frame(width: 224)
            .clipped()
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    private func selectEnvironment() {
        withAnimation(.snappy(duration: 0.2)) {
            selectedProject = ProjectCapabilityStore.environmentSelectionID
            selectedCapability = nil
            expandedGroupIDs.removeAll()
        }
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

    private var visibleCapabilities: [Capability] {
        guard let graph = store.graph else { return [] }
        guard let selectedAgent else { return graph.capabilities }
        return selectedAgent.visibleCapabilities(in: graph)
    }

    private var capabilityDisplayItems: [CapabilityDisplayItem] {
        CapabilityDisplayGrouper().items(for: filteredCapabilities)
    }

    private var agentOptions: [AgentSelection] {
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
}
