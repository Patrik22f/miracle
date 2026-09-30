import SwiftUI

struct OverlayView: View {
    @Bindable var model: AppModel
    let close: () -> Void
    let settings: AppSettings
    let catalog: ModelCatalog
    let installer: SkillInstallModel
    var openSettings: () -> Void = {}
    var modeChanged: () -> Void = {}
    @State private var showingLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.title2).foregroundStyle(.tint)
                Text("Zázrak").font(.title2.weight(.semibold))
                if model.demoMode { Text("Demo").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { showingLibrary = true } label: { Image(systemName: "books.vertical") }
                    .accessibilityLabel("Skill library")
                Button(action: openSettings) { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("Close Zázrak")
                    .keyboardShortcut(.cancelAction)
            }.buttonStyle(.borderless)
            HStack {
                DisplayModeControl(settings: settings, changed: modeChanged)
                Spacer()
                Picker("Application", selection: $model.targetApp) {
                    ForEach(HostApp.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize().accessibilityLabel("Target application")
            }
            Divider()
            HStack {
                Text("Your prompt").font(.headline)
                Spacer()
                Toggle("Live", isOn: Binding(get: { model.liveCaptureEnabled && !model.demoMode }, set: model.setLiveCaptureEnabled))
                    .toggleStyle(.switch).controlSize(.mini).disabled(model.demoMode)
                    .accessibilityLabel("Live capture")
            }
            TextEditor(text: Binding(get: { model.prompt }, set: model.editPrompt))
                .font(.body).scrollContentBackground(.hidden)
                .frame(height: 90).padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
                .accessibilityLabel("Prompt to analyze")
            DisclosureGroup(model.contextLabel) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review the earlier task and decisions. Add anything missing from the visible chat.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { model.contextText }, set: model.editContext))
                        .font(.body).frame(height: 90)
                        .accessibilityLabel("Chat context")
                    if model.context != nil {
                        Button("Clear context") { model.editContext("") }.controlSize(.small)
                    }
                }
            }.font(.caption)
            HStack {
                if model.captureStatus == .permissionRequired {
                    Button("Enable Accessibility", action: AccessibilityPermission.request).controlSize(.small)
                } else if let app = model.sourceApp {
                    Label(app, systemImage: "text.cursor").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: model.cancel)
                } else {
                    Button("Analyze") { model.analyze() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            if model.hasError, let message = model.message {
                Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.demoMode {
                        PromptSuggestionsView(suggestions: model.suggestions, use: model.useSuggestion)
                        Divider()
                    }
                    if let result = model.result {
                        ModelRecommendationView(result: result, host: model.targetApp, settings: settings, catalog: catalog)
                        Text(result.contextLabel).font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Skills").font(.headline)
                                Text("\(result.skills.count)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let count = result.meta.importedCount {
                                    Text("\(count) in library").font(.caption).foregroundStyle(.secondary)
                                }
                                Text(model.demoMode ? "Demo" : result.sourceLabel).font(.caption).foregroundStyle(.secondary)
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
                            Text("Ready for your prompt").font(.callout).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 34)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if !model.hasError, model.message == "Copied" {
                    Label("Copied", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy prompt") { model.copy(includeSkills: false) }.disabled(model.prompt.isEmpty)
                if model.result?.skills.isEmpty == false {
                    Button("Copy with skills") { model.copy(includeSkills: true) }
                        .buttonStyle(.borderedProminent).disabled(model.selected.isEmpty)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingLibrary) {
            SkillLibraryView(host: model.targetApp, settings: settings, installer: installer, openSettings: openSettings)
        }
    }
}
