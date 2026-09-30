import SwiftUI

struct OverlayView: View {
    @Bindable var model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkle").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preflight").font(.title2.bold())
                    Text("The right skills, before you send.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("⌥⌘Return").font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.sourceApp.map { "Prompt from \($0)" } ?? "Your prompt").font(.headline)
                Spacer()
                Toggle("Demo mode", isOn: Binding(get: { model.demoMode }, set: { model.invalidate(); model.demoMode = $0 }))
                    .toggleStyle(.switch).controlSize(.small)
            }
            TextEditor(text: Binding(get: { model.prompt }, set: { model.invalidate(); model.sourceApp = nil; model.prompt = $0 }))
                .font(.body).frame(minHeight: 90, maxHeight: 120)
                .padding(6).background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityLabel("Prompt to analyze")
            HStack {
                Button("Analyze prompt", action: model.analyze)
                    .buttonStyle(.borderedProminent).disabled(model.isLoading || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                if model.isLoading { ProgressView().controlSize(.small); Button("Cancel", action: model.cancel) }
                Spacer()
                Button("Accessibility…", action: FocusedText.requestPermission).buttonStyle(.link)
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
                            Text(model.demoMode ? "Demo fixture" : result.meta.source == "skills.sh" ? "Live search" : "Local catalog")
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
                                HStack {
                                    Text(skill.source).lineLimit(1)
                                    Spacer()
                                    Link("View skill ↗", destination: skill.url)
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
                        ContentUnavailableView("Ready when you are", systemImage: "text.magnifyingglass", description: Text("Focus a prompt in another app and press ⌥⌘Return, or paste it above."))
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
            Text("Prompt stays on your Mac. Live search sends topic labels to skills.sh.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(minWidth: 510, idealWidth: 560, minHeight: 670)
    }
}
