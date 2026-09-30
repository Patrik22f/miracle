import SwiftUI

struct DisplayModeControl: View {
    @Bindable var settings: AppSettings
    var changed: () -> Void = {}
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(DisplayMode.allCases) { mode in
                    Button { settings.mode = mode } label: {
                        if settings.mode == mode { Label(mode.title, systemImage: "checkmark") }
                        else { Text(mode.title) }
                    }
                }
            } label: { Label(settings.mode.title, systemImage: settings.mode.symbol) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel(settings.mode.title)
                .onChange(of: settings.mode) { changed() }
            Button { showingInfo.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                .buttonStyle(.plain).accessibilityLabel("About \(settings.mode.title) mode")
                .popover(isPresented: $showingInfo) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(settings.mode.title, systemImage: settings.mode.symbol).font(.headline)
                        Text(settings.mode.summary).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(18).frame(width: 270)
                }
        }
    }
}

struct ModelRecommendationView: View {
    let result: AnalyzeResponse
    let host: HostApp
    let settings: AppSettings
    let catalog: ModelCatalog
    var compact = false
    var demo = false

    private var models: [RecommendedModel] { demo ? catalog.models(for: host) : settings.availableModels(for: host, catalog: catalog) }
    private var recommendation: RecommendedModel? { ModelRecommendation.choose(from: models, profile: result.model.profile, requestedEffort: result.effort.level) }
    private var efforts: [String] {
        guard let recommendation else { return [] }
        if host == .cursor, !demo, !(settings.detectCursorModels && catalog.cursorDetected), !settings.cursorCustomEffort {
            return recommendation.id.hasPrefix("grok-") ? ["medium"] : []
        }
        return recommendation.efforts
    }
    private var effort: String? {
        ModelRecommendation.effort(supported: efforts, requested: result.effort.level)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Text("Recommended model").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(host.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if let recommendation {
                Text(recommendation.name)
                    .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                    .accessibilityLabel("Recommended model: \(recommendation.name)")
                if let effort {
                    HStack {
                        Text("Effort").foregroundStyle(.secondary)
                        Spacer()
                        Text(effort.capitalized).fontWeight(.medium)
                    }.font(.callout).accessibilityElement(children: .combine)
                }
            } else {
                Text(host == .cursor ? "Choose available models in Settings" : "Open Codex to load models")
                    .font(.callout)
            }
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.18)))
    }
}

struct SkillInstallButton: View {
    let skill: InstallableSkill
    let host: HostApp?
    let settings: AppSettings
    let installer: SkillInstallModel
    var openSettings: (() -> Void)?
    var demoModel: AppModel? = nil

    var body: some View {
        if let demoModel {
            if demoModel.demoInstalledSkills.contains(skill.id) {
                Label("Installed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Install") { demoModel.installDemoSkills([skill.id]) }
                    .controlSize(.small).disabled(!demoModel.demoMode).accessibilityLabel("Install \(skill.name)")
            }
        } else if let host, let root = settings.installRoot(for: host) {
            switch installer.state(skill, root: root) {
            case .installing:
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Installing…") }.font(.caption)
            case .installed:
                Label("Installed", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
            case .failed(let error):
                VStack(alignment: .trailing, spacing: 4) {
                    Button("Retry install") { installer.install(skill, root: root) }
                    Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: 280, alignment: .trailing)
                }
            case nil:
                Button("Install") { installer.install(skill, root: root) }
                    .controlSize(.small)
                    .accessibilityLabel("Install \(skill.name) in \(host.title)")
            }
        } else if host != nil, let openSettings { Button("Choose project…", action: openSettings).controlSize(.small) }
    }
}

struct InstallSelectedSkillsButton: View {
    let skills: [AnalyzeResponse.Skill]
    let selected: Set<String>
    let host: HostApp?
    let settings: AppSettings
    let installer: SkillInstallModel
    var openSettings: (() -> Void)?
    var demoModel: AppModel? = nil

    private var chosen: [InstallableSkill] { skills.filter { selected.contains($0.id) }.map(InstallableSkill.init) }

    var body: some View {
        if let demoModel {
            if !chosen.isEmpty, chosen.allSatisfy({ demoModel.demoInstalledSkills.contains($0.id) }) {
                Label("Selected skills installed", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Install selected skills") { demoModel.installDemoSkills(Set(chosen.map(\.id))) }
                    .buttonStyle(.borderedProminent).disabled(chosen.isEmpty || !demoModel.demoMode)
            }
        } else if let host, let root = settings.installRoot(for: host) {
            let states = chosen.map { installer.state($0, root: root) }
            if states.contains(.installing) {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Installing selected skills…") }
                    .font(.callout)
            } else if !chosen.isEmpty, states.allSatisfy({ $0 == .installed }) {
                Label("Selected skills installed", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Button("Install selected skills") {
                    installer.installSelected(skills.map(InstallableSkill.init), ids: selected, root: root)
                }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty)
            }
        } else if host != nil, let openSettings {
            Button("Choose project…", action: openSettings).buttonStyle(.borderedProminent)
        }
    }
}

struct RecommendedSkillRow: View {
    let skill: AnalyzeResponse.Skill
    @Bindable var model: AppModel
    let settings: AppSettings
    let installer: SkillInstallModel
    var openSettings: (() -> Void)?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Toggle(isOn: Binding(get: { model.selected.contains(skill.id) }, set: { enabled in
                    if enabled { model.selected.insert(skill.id) } else { model.selected.remove(skill.id) }
                })) { Text(skill.name).font(.callout.weight(.medium)).lineLimit(2) }.toggleStyle(.checkbox)
                Spacer(minLength: 8)
                SkillInstallButton(skill: InstallableSkill(skill), host: model.targetApp, settings: settings, installer: installer, openSettings: openSettings, demoModel: model.demoMode ? model : nil)
            }
            if model.result?.bestSkill?.id == skill.id {
                Label("Best match", systemImage: "star.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
            if !compact {
                Text(skill.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("Source", destination: skill.url).font(.caption)
                    Spacer()
                    if let evaluation = skill.evaluation {
                        Text("\(evaluation.score)/100 match").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(.vertical, 8)
    }
}
