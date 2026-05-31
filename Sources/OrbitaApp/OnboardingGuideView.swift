import SwiftUI

// MARK: - Onboarding guide
//
// A first-run, illustrated walkthrough that teaches Orbita's core mental model:
//   1. Welcome
//   2. Scope — "This Mac" (user) vs the current project
//   3. Agent tabs — Agents / Codex / Claude Code / Trae
//   4. Settings, sorting, and the Enabled/Disabled sections
//   5. The three core actions — Disable, Fork, Delete
//   6. Done
//
// Design: editorial / poster layout — a big two-digit numeral, an all-caps eyebrow,
// a large display title with a line break, and emphasized (**bold**) body copy beside
// a live illustration that fills a fixed-height hero band. ZERO new runtime dependencies:
// art is hand-drawn with SwiftUI Canvas/Shape/SF Symbols, themed with `OrbitaTheme`,
// animated with `.spring`/`.symbolEffect`. Small interactions: hoverable tiles,
// tap-to-reveal action cards, clickable progress pills. The card hugs its content and is
// centred so the page reads as a poster, not a tall sheet with a blank lower half.
//
// A language switcher (English / 中文 ▸ 简体 · 繁體) sits in the bottom-right controls so
// users can pick their language during onboarding; it writes the same `orbitaLanguageCode`
// the rest of the app observes, so the whole UI re-localizes live.
//
// Localization: strings resolve live against `LocalizationManager.shared`. They are
// feature-local here to avoid churn in the shared `LocalizationCatalog`.

// MARK: Trilingual + emphasis helpers

@MainActor
private func tr(_ en: String, _ zhHans: String, _ zhHant: String) -> String {
    switch LocalizationManager.shared.language {
    case .english: return en
    case .simplifiedChinese: return zhHans
    case .traditionalChinese: return zhHant
    }
}

/// Renders inline `**bold**` / `` `code` `` markdown in body copy so the poster text can
/// stress key phrases instead of reading as one flat run. Falls back to the raw string if
/// parsing ever fails, so copy never disappears.
private func emphasized(_ markdown: String) -> AttributedString {
    (try? AttributedString(
        markdown: markdown,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(markdown)
}

// MARK: Steps

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case scope
    case agents
    case organize
    case actions
    case ready

    var id: Int { rawValue }

    /// Two-digit poster numeral, e.g. "01".
    var numeral: String { String(format: "%02d", rawValue + 1) }

    /// Small all-caps kicker above the title — the "poster eyebrow".
    @MainActor
    var eyebrow: String {
        switch self {
        case .welcome:  return L("onboarding.eyebrow.welcome")
        case .scope:    return L("onboarding.eyebrow.scope")
        case .agents:   return L("onboarding.eyebrow.agents")
        case .organize: return L("onboarding.eyebrow.organize")
        case .actions:  return L("onboarding.eyebrow.actions")
        case .ready:    return L("onboarding.eyebrow.ready")
        }
    }

    /// Large display title with an intentional line break for poster rhythm.
    @MainActor
    var title: String {
        switch self {
        case .welcome:  return L("onboarding.title.welcome")
        case .scope:    return L("onboarding.title.scope")
        case .agents:   return L("onboarding.title.agents")
        case .organize: return L("onboarding.title.organize")
        case .actions:  return L("onboarding.title.actions")
        case .ready:    return L("onboarding.title.ready")
        }
    }

    /// Body copy with inline `**bold**` emphasis on the load-bearing phrases.
    @MainActor
    var body: String {
        switch self {
        case .welcome:
            return L("onboarding.body.welcome")
        case .scope:
            return L("onboarding.body.scope")
        case .agents:
            return L("onboarding.body.agents")
        case .organize:
            return L("onboarding.body.organize")
        case .actions:
            return L("onboarding.body.actions")
        case .ready:
            return L("onboarding.body.ready")
        }
    }
}

// MARK: Guide view

struct OnboardingGuideView: View {
    /// Called when the user finishes or skips the guide.
    var onFinish: () -> Void

    @ObservedObject private var localization = LocalizationManager.shared
    @AppStorage("orbitaLanguageCode") private var languageCode = OrbitaLanguage.english.rawValue
    @State private var step: OnboardingStep = .welcome
    @State private var forward = true

    private var stepIndex: Int { step.rawValue }
    private var isLast: Bool { step == OnboardingStep.allCases.last }
    private var isFirst: Bool { step == .welcome }

    var body: some View {
        ZStack {
            OrbitaTheme.canvas.ignoresSafeArea()

            // Same drifting-glyph backdrop as the Full Disk Access screen, so the two first-run
            // surfaces share one look.
            FloatingIconBackdrop()
                .allowsHitTesting(false)

            card
                .frame(width: 720, height: Self.cardHeight)
                .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Fixed card height so every step is the same size — otherwise the shorter last pages
    /// (`actions`, `ready`, whose titles/bodies are shorter) render smaller than the rest. The
    /// `Spacer` above the controls absorbs the per-step text-height difference and keeps the
    /// buttons pinned to the bottom.
    private static let cardHeight: CGFloat = 640

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            hero
                .frame(height: 268)
                .padding(.top, 18)
            textBlock
                .padding(.top, 24)
            Spacer(minLength: 16)
            controls
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .orbitaCard(cornerRadius: 22, shadowRadius: 14, shadowY: 8)
    }

    // MARK: Top bar (brand + clickable progress)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40, height: 40)
                .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Orbita")
                    .font(.headline)
                Text(L("settings.guide.card"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            progressDots
        }
    }

    /// Clickable progress pills — tapping one jumps straight to that step.
    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases) { s in
                Button {
                    jump(to: s)
                } label: {
                    Capsule(style: .continuous)
                        .fill(s == step ? OrbitaTheme.prominentControlFill : OrbitaTheme.controlFill)
                        .frame(width: s == step ? 22 : 8, height: 8)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(s.eyebrow)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: step)
        .accessibilityLabel(String(format: L("onboarding.progress.step"), stepIndex + 1, OnboardingStep.allCases.count))
    }

    // MARK: Hero illustration (fixed band, content centred)

    @ViewBuilder
    private var hero: some View {
        ZStack {
            switch step {
            case .welcome:  WelcomeIllustration()
            case .scope:    ScopeIllustration()
            case .agents:   AgentTabsIllustration()
            case .organize: OrganizeIllustration()
            case .actions:  ActionsIllustration()
            case .ready:    ReadyIllustration()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 28)
        .background(OrbitaTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: step)
    }

    // MARK: Editorial text block (big numeral + eyebrow + display title + body)

    private var textBlock: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(step.numeral)
                .font(.system(size: 58, weight: .heavy, design: .rounded))
                .foregroundStyle(OrbitaTheme.strongBorder)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Text(step.eyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(OrbitaTheme.border)
                        .frame(width: 34, height: 1)
                }

                Text(step.title)
                    .font(.system(size: 30, weight: .bold))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)

                Text(emphasized(step.body))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: Controls (skip · language · back/next)

    private var controls: some View {
        HStack(spacing: 10) {
            if !isLast {
                Button(action: finish) {
                    Text(L("onboarding.button.skip"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            languageMenu

            if !isFirst {
                Button(action: back) {
                    Label(L("onboarding.button.back"), systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button(action: advance) {
                Label(
                    isLast ? L("onboarding.button.getStarted") : L("onboarding.button.next"),
                    systemImage: isLast ? "checkmark" : "chevron.right"
                )
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// Bottom-right language switcher mirroring Settings: English / 中文 ▸ (简体 · 繁體).
    /// The nested menu matches the user's "English vs Chinese (with two variants)" model.
    private var languageMenu: some View {
        Menu {
            languageItem(.english)
            Menu(L("onboarding.language.chinese")) {
                languageItem(.simplifiedChinese)
                languageItem(.traditionalChinese)
            }
        } label: {
            Label(currentLanguageShort, systemImage: "globe")
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("onboarding.language.help"))
    }

    private func languageItem(_ language: OrbitaLanguage) -> some View {
        Button {
            setLanguage(language)
        } label: {
            if language.rawValue == languageCode {
                Label(language.title, systemImage: "checkmark")
            } else {
                Text(language.title)
            }
        }
    }

    private var currentLanguageShort: String {
        switch OrbitaLanguage(rawValue: languageCode) ?? .english {
        case .english: return "EN"
        case .simplifiedChinese: return "简"
        case .traditionalChinese: return "繁"
        }
    }

    private func setLanguage(_ language: OrbitaLanguage) {
        languageCode = language.rawValue
        LocalizationManager.shared.setLanguage(language.rawValue)
    }

    // MARK: Navigation

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        forward = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = next }
    }

    private func back() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        forward = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = prev }
    }

    private func jump(to target: OnboardingStep) {
        guard target != step else { return }
        forward = target.rawValue > step.rawValue
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = target }
    }

    private func finish() { onFinish() }
}

// MARK: - Illustration primitives

/// A small labelled "capability tile" used inside several illustrations, echoing the
/// real grid tiles (rounded square + SF Symbol + caption). Lifts on hover.
private struct GuideTile: View {
    var symbol: String
    var caption: String
    var highlighted: Bool = false

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(highlighted ? OrbitaTheme.prominentControlForeground : Color.primary)
                .frame(width: 60, height: 52)
                .background(
                    highlighted ? OrbitaTheme.prominentControlFill : OrbitaTheme.controlFill,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(OrbitaTheme.strongBorder, lineWidth: hovering ? 1.5 : 0)
                }
                .shadow(color: OrbitaTheme.cardShadow, radius: hovering ? 7 : 0, y: hovering ? 4 : 0)
            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

/// Capability types fan in on appear and gently float.
private struct WelcomeIllustration: View {
    @ObservedObject private var localization = LocalizationManager.shared
    private let symbols = ["shippingbox", "wand.and.stars", "server.rack", "terminal", "link", "doc.text"]
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { idx, symbol in
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 70, height: 70)
                    .background(OrbitaTheme.controlFill, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(OrbitaTheme.border)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                    .rotationEffect(.degrees(appeared ? 0 : -6))
                    .animation(.spring(response: 0.55, dampingFraction: 0.72).delay(Double(idx) * 0.07), value: appeared)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
        .accessibilityLabel(L("onboarding.illustration.welcome"))
    }
}

/// Nested rounded rectangles: outer = "This Mac" (user scope), inner = "Project".
private struct ScopeIllustration: View {
    @ObservedObject private var localization = LocalizationManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(L("onboarding.scope.thisMac"), systemImage: "menubar.dock.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            HStack(spacing: 14) {
                GuideTile(symbol: "wand.and.stars", caption: "~/.codex")
                GuideTile(symbol: "shippingbox", caption: "~/.claude")

                // Inner project box.
                VStack(alignment: .leading, spacing: 9) {
                    Label(L("onboarding.scope.project"), systemImage: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        GuideTile(symbol: "wand.and.stars", caption: ".agents", highlighted: true)
                        GuideTile(symbol: "link", caption: ".mcp.json")
                    }
                }
                .padding(14)
                .background(OrbitaTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(OrbitaTheme.strongBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
        }
        .padding(20)
        .background(OrbitaTheme.controlFill.opacity(0.4), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(OrbitaTheme.border)
        }
        .accessibilityLabel(L("onboarding.illustration.scope"))
    }
}

/// A row of four agent tabs with a selection underline that slides — mirrors the real tab strip.
private struct AgentTabsIllustration: View {
    @ObservedObject private var localization = LocalizationManager.shared
    private let tabs: [(String, String)] = [
        ("point.3.connected.trianglepath.dotted", "Agents"),
        ("command", "Codex"),
        ("text.bubble", "Claude"),
        ("sparkles", "Trae"),
    ]
    @State private var selected = 0

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                    VStack(spacing: 6) {
                        Label(tab.1, systemImage: tab.0)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(idx == selected ? Color.primary : .secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                idx == selected ? OrbitaTheme.elevatedSurface : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        Capsule()
                            .fill(idx == selected ? OrbitaTheme.prominentControlFill : Color.clear)
                            .frame(width: 22, height: 3)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { selected = idx }
                    }
                }
            }

            HStack(spacing: 14) {
                GuideTile(symbol: "wand.and.stars", caption: L("onboarding.tile.skill"))
                GuideTile(symbol: "server.rack", caption: "MCP")
                GuideTile(symbol: "doc.text", caption: L("onboarding.tile.rule"))
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            // Gentle auto-cycle of the selected tab to show "switching only re-filters".
            for i in 0..<12 {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    selected = (i + 1) % tabs.count
                }
            }
        }
        .accessibilityLabel(L("onboarding.illustration.agents"))
    }
}

/// A miniature capability list with section headers and a sort control.
private struct OrganizeIllustration: View {
    @ObservedObject private var localization = LocalizationManager.shared
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Sort/filter control column.
            VStack(alignment: .leading, spacing: 11) {
                miniChip(L("onboarding.organize.filter.all"), system: "square.grid.2x2", on: true)
                miniChip(L("collection.type.skills"), system: "wand.and.stars", on: false)
                miniChip("MCP", system: "server.rack", on: false)
                Divider().frame(width: 104)
                Label(L("sort.name"), systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Sectioned list column.
            VStack(alignment: .leading, spacing: 9) {
                sectionHeader(L("onboarding.organize.section.enabled"), count: 2, dot: .green)
                listRow("review-helper", on: true)
                listRow("lark-doc", on: true)
                sectionHeader(L("onboarding.organize.section.disabled"), count: 1, dot: .secondary)
                listRow("legacy-skill", on: false)
            }
            .frame(maxWidth: 320, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L("onboarding.illustration.organize"))
    }

    private func miniChip(_ text: String, system: String, on: Bool) -> some View {
        Label(text, systemImage: system)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(on ? OrbitaTheme.prominentControlForeground : .secondary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(on ? OrbitaTheme.prominentControlFill : OrbitaTheme.controlFill,
                        in: Capsule(style: .continuous))
    }

    private func sectionHeader(_ title: String, count: Int, dot: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(title).font(.system(size: 11, weight: .semibold))
            Text("\(count)").font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func listRow(_ name: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(name).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
            Image(systemName: on ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 13))
                .foregroundStyle(on ? .green : .secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(OrbitaTheme.controlFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// The three core actions as tap-to-reveal cards. Selecting one lifts it and dims the
/// others, so the meaning of Disable / Fork / Delete lands one at a time.
private struct ActionsIllustration: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var selected: Int? = nil
    @State private var pulse = false

    private struct Action {
        let symbol: String
        let title: String
        let detail: String
        let tint: Color
    }

    private var actions: [Action] {
        [
            Action(
                symbol: "eye.slash",
                title: L("onboarding.action.disable.title"),
                detail: L("onboarding.action.disable.detail"),
                tint: .orange
            ),
            Action(
                symbol: "arrow.triangle.branch",
                title: L("onboarding.action.fork.title"),
                detail: L("onboarding.action.fork.detail"),
                tint: .blue
            ),
            Action(
                symbol: "trash",
                title: L("onboarding.action.delete.title"),
                detail: L("onboarding.action.delete.detail"),
                tint: .red
            ),
        ]
    }

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                card(action, index: idx)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { pulse = true }
        .accessibilityLabel(L("onboarding.illustration.actions"))
    }

    private func card(_ action: Action, index: Int) -> some View {
        let isSelected = selected == index
        let dimmed = selected != nil && !isSelected
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                selected = isSelected ? nil : index
            }
        } label: {
            VStack(spacing: 11) {
                Image(systemName: action.symbol)
                    .font(.system(size: 27, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.white : action.tint)
                    .frame(width: 64, height: 56)
                    .background(
                        isSelected ? action.tint : action.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(action.tint.opacity(isSelected ? 0 : 0.28))
                    }
                    .symbolEffect(.pulse, options: .repeating, value: selected == nil && pulse)
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(action.detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(
                isSelected ? action.tint.opacity(0.07) : Color.clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? action.tint.opacity(0.35) : Color.clear)
            }
            .scaleEffect(isSelected ? 1.05 : 1)
            .opacity(dimmed ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ReadyIllustration: View {
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var checked = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .scaleEffect(checked ? 1 : 0.6)
                .opacity(checked ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: checked)
            Label(L("onboarding.ready.openProject"),
                  systemImage: "folder.badge.plus")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear { checked = true }
        .accessibilityLabel(L("onboarding.illustration.ready"))
    }
}

// MARK: - Frequency

/// Controls when the first-run guide auto-presents on launch.
///
/// `firstLaunchOnly` is the default for real users — the guide shows exactly once and
/// never nags again. The other two exist so the guide can be re-checked during
/// development without uninstalling/reinstalling: `always` re-presents on every launch,
/// `never` suppresses the auto-present entirely. In all three modes the Settings
/// "Show guide" button still triggers it on demand.
enum OnboardingGuideFrequency: String, CaseIterable, Identifiable {
    case firstLaunchOnly
    case always
    case never

    var id: String { rawValue }

    static var storageKey: String { "orbitaOnboardingGuideFrequency" }

    @MainActor
    var title: String {
        switch self {
        case .firstLaunchOnly:
            return L("settings.guide.frequency.firstLaunch")
        case .always:
            return L("settings.guide.frequency.always")
        case .never:
            return L("settings.guide.frequency.never")
        }
    }
}

// MARK: - First-run host

/// Wraps `content` and presents the guide as a full-cover, opaque overlay. Because the
/// guide paints over its host, this is attached to the WHOLE gated content (permission
/// gate + main app), so the guide shows FIRST on launch and the screen behind it stays
/// hidden until dismissed — only then is the Full Disk Access screen / main app revealed.
///
/// Reset for testing / "show again":
///     UserDefaults.standard.set(false, forKey: OnboardingGuideHost.completedKey)
struct OnboardingGuideHost<Content: View>: View {
    static var completedKey: String { "orbitaOnboardingGuideCompleted" }

    @ViewBuilder var content: Content
    /// External trigger to re-show the guide (e.g. a Settings button bound to a @State).
    var forcePresented: Binding<Bool>? = nil

    @AppStorage("orbitaOnboardingGuideCompleted") private var completed = false
    @AppStorage("orbitaOnboardingGuideFrequency") private var frequencyRaw = OnboardingGuideFrequency.firstLaunchOnly.rawValue
    /// Whether the user already dismissed the guide during THIS launch. Non-persisted
    /// (`@State`) on purpose: it stops the `always` debug mode from immediately
    /// re-presenting after a dismiss, yet resets on the next launch so `always` still
    /// shows again then.
    @State private var dismissedThisLaunch = false

    private var frequency: OnboardingGuideFrequency {
        OnboardingGuideFrequency(rawValue: frequencyRaw) ?? .firstLaunchOnly
    }

    private var autoPresent: Bool {
        guard !dismissedThisLaunch else { return false }
        switch frequency {
        case .always: return true
        case .never: return false
        case .firstLaunchOnly: return !completed
        }
    }

    private var isPresented: Bool { (forcePresented?.wrappedValue ?? false) || autoPresent }

    var body: some View {
        content
            .overlay {
                if isPresented {
                    OnboardingGuideView(onFinish: dismiss)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(10)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: isPresented)
    }

    private func dismiss() {
        completed = true
        dismissedThisLaunch = true
        forcePresented?.wrappedValue = false
    }
}

extension View {
    /// Present the first-run onboarding guide above this view.
    func orbitaOnboardingGuide(forcePresented: Binding<Bool>? = nil) -> some View {
        OnboardingGuideHost(content: { self }, forcePresented: forcePresented)
    }
}

// MARK: - Reusable spotlight (coach mark on the REAL UI)
//
// The hybrid plan's second half: highlight a region of the live app and float a tooltip
// beside it. Pure SwiftUI anchor-preferences + an even-odd cut-out — no dependency, fully
// macOS-supported. Tag real views with `.onboardingSpotlight("id")` and host the layer
// once with `.onboardingSpotlightLayer(active:message:onNext:)`.

struct OnboardingSpotlightAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Mark this view as a spotlight target identified by `id`.
    func onboardingSpotlight(_ id: String) -> some View {
        anchorPreference(key: OnboardingSpotlightAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Host the spotlight overlay. `active` is the currently highlighted target id (nil = hidden).
    func onboardingSpotlightLayer(
        active: String?,
        message: String,
        onNext: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) -> some View {
        overlayPreferenceValue(OnboardingSpotlightAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let active, let anchor = anchors[active] {
                    OnboardingSpotlightOverlay(
                        rect: proxy[anchor],
                        message: message,
                        onNext: onNext,
                        onSkip: onSkip
                    )
                }
            }
        }
    }
}

private struct OnboardingSpotlightOverlay: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let rect: CGRect
    let message: String
    let onNext: () -> Void
    let onSkip: (() -> Void)?

    private let padding: CGFloat = 8
    private let radius: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let hole = rect.insetBy(dx: -padding, dy: -padding)

            ZStack {
                // Dim everything except the spotlighted rect (even-odd cut-out).
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: proxy.size))
                    p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onNext() }

                // Ring around the target.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(OrbitaTheme.prominentControlFill, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)

                // Tooltip bubble, placed below the target (or above if near the bottom).
                tooltip
                    .frame(maxWidth: 280, alignment: .leading)
                    .position(tooltipPosition(in: proxy.size, hole: hole))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: rect)
        }
    }

    private var tooltip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if let onSkip {
                    Button(L("onboarding.button.skip"), action: onSkip)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(L("onboarding.button.next"), action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: 280, alignment: .leading)
        .orbitaCard(cornerRadius: 14, shadowRadius: 12, shadowY: 6)
    }

    private func tooltipPosition(in size: CGSize, hole: CGRect) -> CGPoint {
        let below = hole.maxY + 70
        let y = below + 80 < size.height ? below : max(90, hole.minY - 70)
        let x = min(max(160, hole.midX), size.width - 160)
        return CGPoint(x: x, y: y)
    }
}

#if DEBUG
#Preview("Onboarding guide") {
    OnboardingGuideView(onFinish: {})
        .frame(width: 940, height: 720)
}
#endif
