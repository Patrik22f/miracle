import SwiftUI

extension AnalyzeResponse {
    var sourceLabel: String {
        switch meta.source {
        case "hybrid": "Imported + public search"
        case "installed": "Installed skills"
        case "skills.sh": "Live search"
        case "catalog": "Local catalog"
        default: "No search needed"
        }
    }
}

struct HelpfulView: View {
    @Bindable var model: AppModel
    let review: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Preflight", systemImage: "sparkle").font(.headline)
                Spacer()
                if let result = model.result {
                    Text(model.demoMode ? "Demo fixture" : result.sourceLabel).font(.caption).foregroundStyle(.secondary)
                }
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Dismiss for this prompt").accessibilityLabel("Dismiss recommendation")
            }
            if let result = model.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if result.skills.isEmpty {
                            Label("Your prompt can stand on its own.", systemImage: "checkmark.circle").font(.callout)
                        }
                        ForEach(result.skills) { skill in
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle(isOn: Binding(get: { model.selected.contains(skill.id) }, set: { enabled in
                                    if enabled { model.selected.insert(skill.id) } else { model.selected.remove(skill.id) }
                                })) { Text(skill.name).font(.callout.weight(.semibold)).lineLimit(2) }
                                    .toggleStyle(.checkbox)
                                Text(skill.reason).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Link(skill.provenance == "installed" ? "Open SKILL.md" : "View skill", destination: skill.url).font(.caption)
                            }
                        }
                        Divider()
                        HStack {
                            Label("\(result.effort.level.capitalized) effort", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text("\(result.model.profile.capitalized) model")
                        }.font(.caption)
                        Text(result.effort.reason).font(.caption).foregroundStyle(.secondary)
                        Text(result.model.reason).font(.caption).foregroundStyle(.secondary)
                        Text("Set model and effort in your AI app.").font(.caption).foregroundStyle(.secondary)
                        ForEach(result.meta.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let message = model.message {
                Label("Couldn’t get recommendations", systemImage: "exclamationmark.circle").font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Review prompt", action: review).buttonStyle(.borderless)
                Spacer()
                Button(model.selected.isEmpty ? "Copy prompt" : "Copy with skills") {
                    model.copy(includeSkills: !model.selected.isEmpty)
                }.buttonStyle(.borderedProminent).disabled(model.result == nil)
            }
            if !model.hasError, let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.6)))
    }
}
