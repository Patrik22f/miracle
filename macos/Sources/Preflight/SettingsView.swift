import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: AppModel
    let catalog: ModelCatalog
    let changed: () -> Void
    let demo: () -> Void
    @State private var page = Page.general
    enum Page: String, CaseIterable { case general = "General", models = "Models", skills = "Skills" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $page) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(20)
            Form {
                switch page {
                case .general:
                    Section("Presentation") {
                        LabeledContent("Mode") { DisplayModeControl(settings: settings, changed: changed) }
                        Toggle("Automatic recommendations", isOn: $settings.automatic).onChange(of: settings.automatic) { changed() }
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
                case .models:
                    Section("Available in Cursor") {
                        ForEach(ModelRecommendation.cursorModels) { option in
                            Toggle(option.name, isOn: Binding(get: { settings.cursorModelIDs.contains(option.id) }, set: { enabled in
                                if enabled { settings.cursorModelIDs.insert(option.id) } else { settings.cursorModelIDs.remove(option.id) }
                            }))
                        }
                        Toggle("Custom effort available", isOn: $settings.cursorCustomEffort)
                    }
                    Section("Available in Codex") {
                        if catalog.codexModels.isEmpty { Text(catalog.error ?? "Loading…").foregroundStyle(.secondary) }
                        ForEach(catalog.codexModels) { model in Text(model.name) }
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
