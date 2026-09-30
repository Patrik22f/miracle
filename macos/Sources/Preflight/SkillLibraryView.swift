import SwiftUI

struct SkillLibraryView: View {
    let host: HostApp?
    let settings: AppSettings
    let installer: SkillInstallModel
    var openSettings: () -> Void = {}
    var demoModel: AppModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var library: SkillLibrary?
    @State private var query = ""
    @State private var provenance = ""
    @State private var source = ""
    @State private var scope = ""
    @State private var purpose = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var importRevision = 0

    private var filteredSkills: [SkillLibrary.Entry] {
        guard let library else { return [] }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return library.skills.filter { skill in
            let text = "\(skill.name) \(skill.description) \(skill.source) \((skill.scopes + skill.purposes).joined(separator: " "))"
            return (provenance.isEmpty || skill.provenance == provenance)
                && (source.isEmpty || skill.source == source)
                && (scope.isEmpty || skill.scopes.contains(scope))
                && (purpose.isEmpty || skill.purposes.contains(purpose))
                && terms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        let visibleSkills = filteredSkills
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Skill library").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                if let library {
                    Text(demoModel == nil ? "\(library.installedCount) installed · \(library.publicCount) public" : "\(library.count) skills").font(.headline)
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                if demoModel == nil {
                    Button(library?.count == 0 ? "Import skills" : "Refresh imports") { importRevision += 1 }
                        .disabled(isLoading)
                }
            }
            TextField("Search skills", text: $query)
                .textFieldStyle(.roundedBorder)
            HStack {
                Picker("Availability", selection: $provenance) {
                    Text("All").tag("")
                    Text("Installed").tag("installed")
                    Text("Public").tag("public-import")
                }
                Picker("Source", selection: $source) {
                    Text("All sources").tag("")
                    ForEach(Array(Set(library?.skills.map(\.source) ?? [])).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
            HStack {
                Picker("Platform", selection: $scope) {
                    Text("All platforms").tag("")
                    ForEach(Array(Set(library?.skills.flatMap(\.scopes) ?? [])).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Purpose", selection: $purpose) {
                    Text("All purposes").tag("")
                    ForEach(Array(Set(library?.skills.flatMap(\.purposes) ?? [])).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
            HStack {
                Text("\(visibleSkills.count) matching skills").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear filters") { query = ""; provenance = ""; source = ""; scope = ""; purpose = "" }
                    .controlSize(.small)
                    .disabled(query.isEmpty && provenance.isEmpty && source.isEmpty && scope.isEmpty && purpose.isEmpty)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.secondary) }
            if let warning = library?.warnings.first {
                Text(warning).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            List(visibleSkills) { skill in
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
                    HStack {
                        Link("Source", destination: skill.url).font(.caption)
                        Spacer()
                        SkillInstallButton(skill: InstallableSkill(skill), host: host, settings: settings, installer: installer, openSettings: openSettings, demoModel: demoModel)
                    }
                }.padding(.vertical, 5)
            }.overlay {
                if library != nil && visibleSkills.isEmpty && !isLoading {
                    ContentUnavailableView("No matching skills", systemImage: "magnifyingglass",
                        description: Text("Clear filters or refresh imports to update your library."))
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 540)
        .task(id: importRevision) { await load(importSkills: importRevision > 0) }
    }

    @MainActor private func load(importSkills: Bool) async {
        if demoModel != nil { library = DemoCatalog.library; return }
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
            self.error = error.localizedDescription
        }
    }
}
