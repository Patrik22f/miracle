import SwiftUI

struct OverlayView: View {
    @Bindable var model: AppModel
    let close: () -> Void
    let settings: AppSettings
    let catalog: ModelCatalog
    let installer: SkillInstallModel
    var openSettings: () -> Void = {}
    var modeChanged: () -> Void = {}
    var openDemo: () -> Void = {}
    @State private var showingLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                MiracleMark().foregroundStyle(.tint)
                Text("Miracle").font(.title2.weight(.semibold))
                if model.demoMode { Button("Shopfront", action: openDemo).font(.caption) }
                Spacer()
                Button { showingLibrary = true } label: { Image(systemName: "books.vertical") }
                    .accessibilityLabel("Skill library")
                Button(action: openSettings) { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("Close Miracle")
                    .keyboardShortcut(.cancelAction)
            }.buttonStyle(.borderless)
            HStack {
                DisplayModeControl(settings: settings, changed: modeChanged)
                Spacer()
                if let host = model.targetApp {
                    Label(host.title, systemImage: "app").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Text(promptPreview)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Prompt preview: \(promptPreview)")
                if model.isLoading {
                    ProgressView().controlSize(.mini).accessibilityLabel("Analyzing prompt")
                    Button("Cancel", action: model.cancel).controlSize(.small)
                } else if !model.prompt.isEmpty, model.targetApp != nil {
                    Button { model.analyze() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).accessibilityLabel("Analyze prompt again")
                }
            }
            if model.captureStatus == .permissionRequired {
                Button("Enable Accessibility", action: AccessibilityPermission.request).controlSize(.small)
            }
            if model.hasError, let message = model.message {
                Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.demoMode {
                        if !model.liveCaptureEnabled {
                            DisclosureGroup("Review draft") {
                                TextEditor(text: Binding(get: { model.prompt }, set: model.editPrompt))
                                    .font(.body).frame(height: 90)
                                    .accessibilityLabel("Draft prompt")
                                HStack {
                                    Button("Copy draft") { model.copy(includeSkills: false) }
                                    Button("Resume live capture") { model.setLiveCaptureEnabled(true) }
                                }.controlSize(.small)
                            }
                        }
                        DisclosureGroup(model.contextLabel) {
                            TextEditor(text: Binding(get: { model.contextText }, set: model.editContext))
                                .font(.body).frame(height: 90)
                                .accessibilityLabel("Chat context")
                            if model.context != nil {
                                Button("Clear context") { model.editContext("") }.controlSize(.small)
                            }
                        }.font(.caption)
                    }
                    if !model.demoMode {
                        PromptSuggestionsView(suggestions: model.suggestions, use: model.useSuggestion)
                        Divider()
                    }
                    if let result = model.result {
                        if let host = model.targetApp {
                            ModelRecommendationView(result: result, host: host, settings: settings, catalog: catalog, demo: model.demoMode)
                        }
                        if !model.demoMode { Text(result.contextLabel).font(.caption).foregroundStyle(.secondary) }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Skills").font(.headline)
                                Text("\(result.skills.count)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let count = result.meta.importedCount {
                                    Text("\(count) in library").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(result.sourceLabel).font(.caption).foregroundStyle(.secondary)
                            }.padding(.bottom, 4)
                            if result.skills.isEmpty { Text(result.emptySkillsLabel).font(.callout).foregroundStyle(.secondary) }
                            ForEach(result.skills) { skill in
                                RecommendedSkillRow(skill: skill, model: model, settings: settings, installer: installer, openSettings: openSettings)
                                if skill.id != result.skills.last?.id { Divider() }
                            }
                        }
                    } else if !model.isLoading, !model.hasError {
                        VStack(spacing: 10) {
                            Image(systemName: "text.magnifyingglass").font(.largeTitle).foregroundStyle(.tertiary)
                            Text("Waiting for a prompt").font(.callout).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 34)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let result = model.result, !result.skills.isEmpty, model.targetApp != nil {
                Divider()
                HStack {
                    Text("\(result.skills.filter { model.selected.contains($0.id) }.count) selected")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    InstallSelectedSkillsButton(skills: result.skills, selected: model.selected, host: model.targetApp,
                        settings: settings, installer: installer, openSettings: openSettings, demoModel: model.demoMode ? model : nil)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingLibrary) {
            SkillLibraryView(host: model.targetApp, settings: settings, installer: installer, openSettings: openSettings, demoModel: model.demoMode ? model : nil)
        }
    }

    private var promptPreview: String {
        guard (model.targetApp != nil || !model.liveCaptureEnabled), !model.prompt.isEmpty else { return "—" }
        let beginning = model.prompt.prefix(240).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return beginning + (model.prompt.count > 240 ? "…" : "")
    }
}
