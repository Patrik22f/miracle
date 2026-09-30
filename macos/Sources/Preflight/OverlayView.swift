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
                Text("Preflight").font(.title2.weight(.semibold))
                if model.demoMode { Text("Demo").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { showingLibrary = true } label: { Image(systemName: "books.vertical") }
                    .accessibilityLabel("Skill library")
                Button(action: openSettings) { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel("Close Preflight")
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Prompt").font(.subheadline.weight(.medium))
                    Spacer()
                    if model.isLoading {
                        ProgressView().controlSize(.mini).accessibilityLabel("Analyzing prompt")
                        Button("Cancel", action: model.cancel).controlSize(.small)
                    } else if !model.prompt.isEmpty, model.targetApp != nil {
                        Button { model.analyze() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).accessibilityLabel("Analyze prompt again")
                    }
                }
                Text(promptPreview)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Prompt preview: \(promptPreview)")
            }
            if model.captureStatus == .permissionRequired {
                Button("Enable Accessibility", action: AccessibilityPermission.request).controlSize(.small)
            }
            if model.hasError, let message = model.message {
                Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let result = model.result, let host = model.targetApp {
                        ModelRecommendationView(result: result, host: host, settings: settings, catalog: catalog)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Skills").font(.headline)
                                Text("\(result.skills.count)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text(model.demoMode ? "Demo" : result.sourceLabel).font(.caption).foregroundStyle(.secondary)
                            }.padding(.bottom, 4)
                            if result.skills.isEmpty { Text("No additional skills").font(.callout).foregroundStyle(.secondary) }
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
                        settings: settings, installer: installer, openSettings: openSettings)
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

    private var promptPreview: String {
        guard model.targetApp != nil, !model.prompt.isEmpty else { return "—" }
        let beginning = model.prompt.prefix(240).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return beginning + (model.prompt.count > 240 ? "…" : "")
    }
}
