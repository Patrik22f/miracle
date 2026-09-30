import SwiftUI

struct PromptSuggestionsView: View {
    @Bindable var suggestions: PromptSuggestionsModel
    var compact = false
    var use: (PromptSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your next task", systemImage: "sparkles").font(.headline)
                Spacer()
                if suggestions.isLoading { ProgressView().controlSize(.small) }
                Button(action: suggestions.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).accessibilityLabel("Refresh prompt suggestions")
                    .disabled(suggestions.projectPath.isEmpty || !suggestions.enabled || suggestions.isLoading)
            }
            if !suggestions.enabled {
                Button("Enable prompt suggestions") { suggestions.setEnabled(true) }
            } else {
                HStack {
                    Button(action: suggestions.chooseProject) {
                        Label(suggestions.projectName, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                    }.buttonStyle(.borderless).help(suggestions.projectPath)
                    if !suggestions.selectedProjectPath.isEmpty {
                        Text("Selected project").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if suggestions.projectPath.isEmpty {
                    Text("Choose your code folder once. Miracle follows changes and suggests three next tasks using Groq.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let response = suggestions.response, response.status == "ready" {
                    if !compact, let summary = response.summary {
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                    }
                    if let project = response.project {
                        Text("\(project.sampledFileCount) files sampled · \(project.fileCount) indexed · Groq")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(response.suggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(suggestion.title).font(.subheadline.weight(.semibold))
                            if !compact {
                                Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                                DisclosureGroup("View prompt") {
                                    Text(suggestion.prompt).font(.callout).textSelection(.enabled)
                                    Text(suggestion.files.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                                }.font(.caption)
                            }
                            HStack {
                                Button("Use draft") { use(suggestion) }
                                Button(suggestions.copiedID == suggestion.id ? "Copied" : "Copy prompt") { suggestions.copy(suggestion) }
                            }.controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else if let message = suggestions.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                } else if suggestions.isLoading {
                    Text("Reading the project and preparing your next tasks…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
