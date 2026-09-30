import SwiftUI

struct OverlayView: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var showingLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkle").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preflight").font(.title2.bold())
                    Text("The right skills, before you send.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Skill library", systemImage: "books.vertical") { showingLibrary = true }
                    .controlSize(.small)
                Text("⌥⌘Return").font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            HStack {
                Text("Your prompt").font(.headline)
                Spacer()
                Toggle("Demo mode", isOn: Binding(get: { model.demoMode }, set: model.setDemoMode))
                    .toggleStyle(.switch).controlSize(.small)
            }
            LiveCaptureView(model: model)
            TextEditor(text: Binding(get: { model.prompt }, set: model.editPrompt))
                .font(.body).frame(minHeight: 90, maxHeight: 120)
                .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityLabel("Prompt to analyze")
            HStack {
                Button("Analyze prompt") { model.analyze() }
                    .buttonStyle(.borderedProminent).disabled(model.isLoading || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                if model.isLoading { ProgressView().controlSize(.small); Button("Cancel", action: model.cancel) }
                Spacer()
                Button("Accessibility…", action: AccessibilityPermission.request).buttonStyle(.link)
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let result = model.result {
                        HStack {
                            Text("Recommended skills").font(.headline)
                            Spacer()
                            Text(model.demoMode ? "Demo fixture" : result.meta.source == "hybrid" ? "Imported + public search" : result.meta.source == "installed" ? "Installed skills" : result.meta.source == "skills.sh" ? "Live search" : "Local catalog")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let count = result.meta.importedCount {
                            Text("\(count) imported skills evaluated · Up to 3 complementary suggestions")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if result.skills.isEmpty {
                            Text("No matching skill found. Your prompt can stand on its own.").foregroundStyle(.secondary)
                        }
                        ForEach(result.skills) { skill in
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle(isOn: Binding(get: { model.selected.contains(skill.id) }, set: { enabled in
                                    if enabled { model.selected.insert(skill.id) } else { model.selected.remove(skill.id) }
                                })) { Text(skill.name).font(.headline) }
                                Text(skill.reason).font(.callout)
                                if let evaluation = skill.evaluation {
                                    SkillEvaluationView(evaluation: evaluation)
                                }
                                HStack {
                                    Text(skill.provenance == "installed" ? "Installed on this Mac" : skill.source).lineLimit(1)
                                    Spacer()
                                    Link(skill.provenance == "installed" ? "Open SKILL.md" : "View skill ↗", destination: skill.url)
                                }.font(.caption).foregroundStyle(.secondary)
                            }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }
                        Divider()
                        HStack {
                            Label("\(result.effort.level.capitalized) effort", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text("\(result.model.profile.capitalized) model")
                        }.font(.callout)
                        Text("Suggestions only. Set model and effort in your AI app.").font(.caption).foregroundStyle(.secondary)
                        ForEach(result.meta.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    } else if !model.isLoading {
                        ContentUnavailableView("Ready when you are", systemImage: "text.magnifyingglass", description: Text("With Live capture on, type in another app and your text appears above. Choose Analyze prompt when you’re ready."))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy original") { model.copy(includeSkills: false) }.disabled(model.prompt.isEmpty)
                Button("Copy with skills") { model.copy(includeSkills: true) }
                    .buttonStyle(.borderedProminent).disabled(model.result == nil || model.selected.isEmpty)
            }
            Text("Imported skills stay on your Mac. Public search sends topic labels to skills.sh.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(minWidth: 510, idealWidth: 560, minHeight: 670)
        .sheet(isPresented: $showingLibrary) { SkillLibraryView() }
    }
}

private struct SkillEvaluationView: View {
    let evaluation: AnalyzeResponse.Evaluation

    var body: some View {
        DisclosureGroup("Why this skill · \(evaluation.score)/100 fit") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(evaluation.criteria) { criterion in
                    HStack {
                        Text(criterion.label)
                        Spacer()
                        Text("\(criterion.points)/\(criterion.maximum)").monospacedDigit()
                    }
                }
                Text("Minimum fit: \(evaluation.threshold). This score measures the match, not skill quality.")
                    .foregroundStyle(.secondary)
            }.font(.caption).padding(.top, 4)
        }.font(.caption)
    }
}

private struct LiveCaptureView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Toggle("Live capture", isOn: Binding(
                    get: { model.liveCaptureEnabled && !model.demoMode },
                    set: model.setLiveCaptureEnabled
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.demoMode)
                .help("Follow the focused text field in other apps. Editing here pauses capture.")
                Spacer()
                if let app = model.sourceApp {
                    Text("Captured from \(app)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Label(model.captureStatus.description, systemImage: model.captureStatus.symbol)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.captureStatus == .permissionRequired {
                Button("Enable Accessibility…", action: AccessibilityPermission.request)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
