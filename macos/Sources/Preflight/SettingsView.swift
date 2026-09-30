import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: AppModel
    let catalog: ModelCatalog
    let changed: () -> Void
    let demo: () -> Void
    @State private var page = Page.general
    enum Page: String, CaseIterable { case general = "General", prompts = "Prompts", models = "Models", skills = "Skills" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(20)
            Form {
                switch page {
                case .general:
                    Section("Presentation") {
                        LabeledContent("Display mode") { DisplayModeControl(settings: settings, changed: changed) }
                        Toggle("Automatic recommendations", isOn: $settings.automatic).onChange(of: settings.automatic) { changed() }
                        Toggle("Live capture", isOn: Binding(get: { model.liveCaptureEnabled }, set: model.setLiveCaptureEnabled))
                    }
                    Section("Permissions") {
                        LabeledContent("Accessibility") {
                            if settings.permissionGranted { Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                            else { Button("Enable…", action: AccessibilityPermission.request) }
                        }
                    }
                    Section {
                        Toggle("Demo mode", isOn: Binding(get: { model.demoMode }, set: { enabled in
                            if enabled { demo() } else { model.setDemoMode(false) }
                        }))
                    }
                case .prompts:
                    Section("Your next task") {
                        Toggle("Suggest prompts automatically", isOn: Binding(get: { model.suggestions.enabled }, set: model.suggestions.setEnabled))
                        LabeledContent("Project") {
                            Button(model.suggestions.projectName, action: model.suggestions.chooseProject)
                        }
                        if !model.suggestions.projectPath.isEmpty {
                            Text(model.suggestions.projectPath).font(.caption).textSelection(.enabled)
                        }
                        if !model.suggestions.selectedProjectPath.isEmpty {
                            Button("Follow the active project's document") { model.suggestions.selectProject("") }
                        }
                        Text("Zázrak checks for code changes every 15 seconds. It uses README files, project structure, source excerpts, and available chat context to suggest three next tasks.")
                            .font(.callout)
                    }
                    Section("Groq") {
                        Text("Selected code excerpts and prompt/chat context are sent to Groq. Environment files, common secret files, ignored files in Git projects, and generated folders are excluded. Common credentials are redacted. Suggestions stay in memory.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Configure GROQ_API_KEY in the local backend's .env file. The default model is openai/gpt-oss-120b, as used by Notamhelp.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Groq API keys", destination: URL(string: "https://console.groq.com/keys")!)
                    }
                case .models:
                    Section("Available in Cursor") {
                        Toggle("Detect models from Cursor", isOn: $settings.detectCursorModels)
                        if let error = catalog.cursorError { Text(error).font(.caption).foregroundStyle(.secondary) }
                        ForEach(catalog.models(for: .cursor)) { option in
                            if settings.detectCursorModels && catalog.cursorDetected {
                                if option.enabled { LabeledContent(option.name, value: option.profile.capitalized) }
                            } else {
                            Toggle(option.name, isOn: Binding(get: { settings.cursorModelIDs.contains(option.id) }, set: { enabled in
                                if enabled { settings.cursorModelIDs.insert(option.id) } else { settings.cursorModelIDs.remove(option.id) }
                            }))
                            }
                        }
                        if !settings.detectCursorModels || !catalog.cursorDetected {
                            Toggle("Custom effort available", isOn: $settings.cursorCustomEffort)
                        }
                        Button("Refresh models") { Task { await catalog.refresh() } }
                    }
                    Section("Available in Codex") {
                        if catalog.codexModels.isEmpty { Text(catalog.error ?? "Loading…").foregroundStyle(.secondary) }
                        ForEach(catalog.codexModels) { model in LabeledContent(model.name, value: model.profile.capitalized) }
                        Button("Refresh models") { Task { await catalog.refresh() } }
                    }
                case .skills:
                    Section("Installation") {
                        Picker("Location", selection: $settings.installInProject) {
                            Text("This Mac").tag(false)
                            Text("Project").tag(true)
                        }
                        if settings.installInProject {
                            LabeledContent("Project") {
                                Button(settings.projectPath.isEmpty ? "Choose folder…" : URL(fileURLWithPath: settings.projectPath).lastPathComponent) { chooseProject() }
                            }
                        }
                        LabeledContent("Cursor", value: settings.installRoot(for: .cursor)?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Choose a project")
                        LabeledContent("Codex", value: settings.installRoot(for: .codex)?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "Choose a project")
                    }
                }
            }.formStyle(.grouped)
        }.frame(width: 540, height: 550)
    }

    private func chooseProject() {
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = false
        chooser.prompt = "Choose project"
        if chooser.runModal() == .OK, let url = chooser.url { settings.projectPath = url.path }
    }
}
