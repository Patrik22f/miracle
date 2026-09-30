import Foundation

/// A small, deterministic presentation catalog. It never calls the production API.
enum DemoCatalog {
    struct Scenario: Identifiable, Sendable {
        let id: String
        let title: String
        let prompt: String
    }

    static let scenarios: [Scenario] = [
        .init(id: "database", title: "1. Přidat databázi", prompt: "Chceme do tohoto webu integrovat databázi pro produkty, zákazníky a objednávky. Navrhni vhodné řešení a připrav propojení."),
        .init(id: "launch", title: "2. Design, texty a iOS", prompt: "Předělej design tohoto webu ve stylu Apple.com. Přepiš nadpisy a texty podle marketingových copywriting zásad a připrav nativní iOS aplikaci ve SwiftUI.")
    ]

    static let skills: [AnalyzeResponse.Skill] = [
        skill("supabase/agent-skills", "supabase-postgres-best-practices", "Postgres query and database design guidance."),
        skill("anthropics/skills", "frontend-design", "Build considered web interfaces."),
        skill("coreyhaines31/marketingskills", "copywriting", "Write clear marketing headlines, website copy and calls to action."),
        skill("avdlee/swiftui-agent-skill", "swiftui-expert-skill", "Build native iOS interfaces with SwiftUI and sound state management.")
    ]

    private static func skill(_ source: String, _ name: String, _ description: String) -> AnalyzeResponse.Skill {
        .init(id: "\(source)/\(name)", name: name, source: source, description: description,
              url: URL(string: "https://skills.sh/\(source)/\(name)")!,
              repositoryUrl: URL(string: "https://github.com/\(source)")!, installs: nil,
              provenance: "catalog", reason: description, confidence: 0.8, security: "not-audited")
    }

    static func analyze(_ prompt: String) -> AnalyzeResponse {
        let words = Set(prompt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        func has(_ terms: String...) -> Bool { !words.isDisjoint(with: terms) }
        let database = has("postgres", "postgresql", "supabase", "sql", "database", "databaze", "databazi")
        let design = has("design", "redesign", "typography", "typografie", "vzhled")
        let copywriting = has("copywriting", "marketing", "marketingovych", "marketingove", "headlines", "nadpisy", "texty")
        let swift = has("swift", "swiftui", "ios", "iphone")
        var names = Set<String>()
        if design { names.insert("frontend-design") }
        if database { names.insert("supabase-postgres-best-practices") }
        if copywriting { names.insert("copywriting") }
        if swift { names.insert("swiftui-expert-skill") }
        let matches = Array(skills.filter { names.contains($0.name) }.prefix(3))
        let profile = database || swift ? "capable" : matches.isEmpty ? "fast" : "balanced"
        let effort = profile == "capable" ? "high" : profile == "fast" ? "low" : "medium"
        return .init(schemaVersion: "1.0", requestId: "demo-\(UUID())",
                     analysis: .init(intent: "demo", tags: [], queries: []),
                     effort: .init(level: effort, reason: "Offline presentation example."),
                     model: .init(profile: profile, reason: "Offline presentation example."), skills: matches,
                     meta: .init(source: "demo", ranking: "demo-keywords-v1", durationMs: 0, warnings: []))
    }

    static var library: SkillLibrary {
        .init(count: skills.count, installedCount: 0, publicCount: skills.count, warnings: [], skills: skills.map {
            .init(id: $0.id, name: $0.name, description: $0.description, source: $0.source,
                  provenance: "catalog", url: $0.url, scopes: [], purposes: [])
        })
    }
}
