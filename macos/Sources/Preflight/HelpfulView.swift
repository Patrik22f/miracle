import SwiftUI

extension AnalyzeResponse {
    var sourceLabel: String {
        switch meta.source {
        case "demo": ""
        case "library": "Studied library"
        case "hybrid": "Library + search"
        case "installed": "Installed"
        case "skills.sh": "Live search"
        case "catalog": "Offline"
        default: ""
        }
    }
    var contextLabel: String {
        switch analysis.context?.status {
        case "used": analysis.context?.truncated == true ? "Using partial chat context" : "Using chat context"
        case "missing": "Chat context needed"
        case "not-needed": "Using the latest request"
        default: "Chat context unavailable"
        }
    }

    var emptySkillsLabel: String {
        analysis.context?.status == "missing" ? "Add the earlier task to find relevant skills." : "No sufficiently supported skill match in this library."
    }

}

struct HelpfulView: View {
    @Bindable var model: AppModel
    let settings: AppSettings
    let catalog: ModelCatalog
    let installer: SkillInstallModel
    let dismiss: () -> Void
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack {
                    MiracleMark(size: 18).foregroundStyle(.tint)
                    Text("Miracle").font(.headline)
                    Spacer()
                    Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(height: 28)
                .overlay { HelpfulPanelDragArea().accessibilityHidden(true) }
                .help("Move recommendations")
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss recommendation")
            }
            if model.result != nil || model.suggestions.response?.status == "ready" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.suggestions.response?.status == "ready" {
                            PromptSuggestionsView(suggestions: model.suggestions, compact: true) { suggestion in
                                model.useSuggestion(suggestion)
                                review()
                            }
                        }
                        if let result = model.result {
                            if let host = model.targetApp {
                                ModelRecommendationView(result: result, host: host, settings: settings, catalog: catalog, compact: true, demo: model.demoMode)
                            }
                            if !model.demoMode { Text(result.contextLabel).font(.caption).foregroundStyle(.secondary) }
                            if result.skills.isEmpty {
                                Text(result.emptySkillsLabel).font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if result.analysis.context?.status == "missing" {
                                Button("Add context", action: review).buttonStyle(.borderless)
                            }
                            ForEach(result.skills) { skill in
                                RecommendedSkillRow(skill: skill, model: model, settings: settings, installer: installer, compact: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let message = model.message {
                Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            HStack {
                if let result = model.result {
                    Text(result.sourceLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let result = model.result, !result.skills.isEmpty {
                    InstallSelectedSkillsButton(skills: result.skills, selected: model.selected, host: model.targetApp,
                        settings: settings, installer: installer, demoModel: model.demoMode ? model : nil)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.6)))
    }
}
