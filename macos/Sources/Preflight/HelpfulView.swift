import SwiftUI

extension AnalyzeResponse {
    var sourceLabel: String {
        switch meta.source {
        case "hybrid": "Library + search"
        case "installed": "Installed"
        case "skills.sh": "Live search"
        case "catalog": "Offline"
        default: ""
        }
    }
}

struct HelpfulView: View {
    @Bindable var model: AppModel
    let settings: AppSettings
    let catalog: ModelCatalog
    let installer: SkillInstallModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Preflight", systemImage: "sparkle").font(.headline)
                Spacer()
                if model.demoMode { Text("Demo").font(.caption).foregroundStyle(.secondary) }
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss recommendation")
            }
            if let result = model.result {
                ModelRecommendationView(result: result, host: model.targetApp, settings: settings, catalog: catalog, compact: true)
                if !result.skills.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(result.skills) { skill in
                                RecommendedSkillRow(skill: skill, model: model, settings: settings, installer: installer, compact: true)
                            }
                        }
                    }
                }
            } else if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            HStack {
                if let result = model.result {
                    Text(result.sourceLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.selected.isEmpty ? "Copy prompt" : "Copy with skills") {
                    model.copy(includeSkills: !model.selected.isEmpty)
                }.buttonStyle(.borderedProminent).disabled(model.result == nil)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.6)))
    }
}
