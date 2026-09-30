import SwiftUI

struct SkillLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var library: SkillLibrary?
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var importRevision = 0

    private var filteredSkills: [SkillLibrary.Entry] {
        guard let library else { return [] }
        guard !query.isEmpty else { return library.skills }
        return library.skills.filter {
            "\($0.name) \($0.description) \($0.source)".localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Skill library").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Import installed skills and a public starter collection. Analyze also searches skills.sh for more candidates.")
                .foregroundStyle(.secondary)
            HStack {
                if let library {
                    Text("\(library.installedCount) installed · \(library.publicCount) public").font(.headline)
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button(library?.count == 0 ? "Import skills" : "Refresh imports") { importRevision += 1 }
                    .disabled(isLoading)
            }
            TextField("Search imported skills", text: $query)
                .textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            if let library {
                ForEach(library.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            List(filteredSkills) { skill in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(skill.name).font(.headline)
                        Spacer()
                        Text(skill.provenance == "installed" ? "Installed" : "Public").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(skill.description).font(.callout).lineLimit(3)
                    if !skill.scopes.isEmpty || !skill.purposes.isEmpty {
                        Text((skill.scopes + skill.purposes).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Link("Read SKILL.md", destination: skill.url).font(.caption)
                }.padding(.vertical, 5)
            }
            Text("Imports index SKILL.md instructions; they do not install tools or execute skill commands. Copied local paths work in AI apps with access to this Mac.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 540)
        .task(id: importRevision) { await load(importSkills: importRevision > 0) }
    }

    @MainActor private func load(importSkills: Bool) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await APIClient().library(importSkills: importSkills)
            guard !Task.isCancelled else { return }
            library = result
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "\(error.localizedDescription) Start the API with npm start."
        }
    }
}
