import SwiftUI

struct DisplayModeControl: View {
    @Bindable var settings: AppSettings
    var changed: () -> Void = {}
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Display mode", selection: $settings.mode) {
                    ForEach(DisplayMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                }
            } label: { Label(settings.mode.title, systemImage: settings.mode.symbol) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Display mode")
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
    @State private var chosenModelID: String?
    @State private var chosenEffort: String?

    private var models: [RecommendedModel] { settings.availableModels(for: host, catalog: catalog) }
    private var recommendation: RecommendedModel? { ModelRecommendation.choose(from: models, profile: result.model.profile, requestedEffort: result.effort.level) }
    private var chosen: RecommendedModel? { models.first { $0.id == chosenModelID } ?? recommendation }
    private var efforts: [String] {
        guard let chosen else { return [] }
        if host == .cursor, !(settings.detectCursorModels && catalog.cursorDetected), !settings.cursorCustomEffort {
            return chosen.id.hasPrefix("grok-") ? ["medium"] : []
        }
        return chosen.efforts
    }
    private var effort: String? {
        if let chosenEffort, efforts.contains(chosenEffort) { return chosenEffort }
        return ModelRecommendation.effort(supported: efforts, requested: result.effort.level)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack {
                Text("Recommended model").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(host.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if let chosen {
                Menu {
                    ForEach(models) { option in
                        Button {
                            chosenModelID = option.id
                            chosenEffort = nil
                        } label: {
                            if chosen.id == option.id { Label(option.name, systemImage: "checkmark") }
                            else { Text(option.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(chosen.name).font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Recommended model: \(chosen.name)")
                if let effort {
                    if efforts.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Effort").foregroundStyle(.secondary)
                            Picker("Effort", selection: Binding(get: { effort }, set: { chosenEffort = $0 })) {
                                ForEach(efforts, id: \.self) { Text($0.capitalized).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                                .accessibilityLabel("Effort")
                        }.font(.callout)
                    } else {
                        HStack {
                            Text("Effort").foregroundStyle(.secondary)
                            Spacer()
                            Text(effort.capitalized).fontWeight(.medium)
                        }.font(.callout)
                    }
                } else {
                    Text("Effort is managed by \(host.title) for this model.").font(.caption).foregroundStyle(.secondary)
                }
                Text(result.effort.reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !compact {
                    Text(chosenModelID == nil ? ModelRecommendation.reason(for: chosen, profile: result.model.profile, availableCount: models.count) : "You selected this model for \(host.title).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(host == .codex ? "Models and effort from Codex’s local catalog" : settings.detectCursorModels && catalog.cursorDetected ? "Models and effort from Cursor’s local settings" : "Models from your manual selection")
                        .font(.caption2).foregroundStyle(.secondary)
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
        .onChange(of: result.requestId) { chosenModelID = nil; chosenEffort = nil }
        .onChange(of: host) { chosenModelID = nil; chosenEffort = nil }
    }
}

struct SkillInstallButton: View {
    let skill: InstallableSkill
    let host: HostApp
    let settings: AppSettings
    let installer: SkillInstallModel
    var openSettings: (() -> Void)?

    var body: some View {
        if let root = settings.installRoot(for: host) {
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
                Button(settings.installInProject ? "Install in project" : "Install in \(host.title)") { installer.install(skill, root: root) }
                    .controlSize(.small)
            }
        } else if let openSettings { Button("Choose project…", action: openSettings).controlSize(.small) }
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
                SkillInstallButton(skill: InstallableSkill(skill), host: model.targetApp, settings: settings, installer: installer, openSettings: openSettings)
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
