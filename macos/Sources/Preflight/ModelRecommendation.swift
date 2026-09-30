import Foundation
import Observation

enum HostApp: String, CaseIterable, Identifiable, Sendable {
    case cursor, codex
    var id: String { rawValue }
    var title: String { rawValue == "cursor" ? "Cursor" : "Codex" }
    var skillsDirectory: String { self == .cursor ? ".cursor/skills" : ".codex/skills" }

    static func detect(_ source: PromptSource?) -> Self? {
        switch source?.bundleIdentifier {
        case "com.todesktop.230313mzl4w4u92": .cursor
        case "com.openai.codex": .codex
        default: nil
        }
    }
}

struct RecommendedModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let host: HostApp
    let profile: String
    let efforts: [String]
}

enum ModelRecommendation {
    // Cursor's documented catalog, checked 2026-09-30. Account availability is selected in Settings.
    static let cursorModels: [RecommendedModel] = [
        .init(id: "grok-4.6", name: "Grok 4.6", host: .cursor, profile: "balanced", efforts: ["low", "medium", "high", "xhigh"]),
        .init(id: "grok-4.7", name: "Grok 4.7", host: .cursor, profile: "capable", efforts: ["low", "medium", "high", "xhigh"]),
        .init(id: "composer-2.5", name: "Composer 2.5", host: .cursor, profile: "fast", efforts: []),
        .init(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", host: .cursor, profile: "capable", efforts: []),
        .init(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", host: .cursor, profile: "balanced", efforts: []),
        .init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", host: .cursor, profile: "fast", efforts: [])
    ]

    static func choose(from models: [RecommendedModel], profile: String) -> RecommendedModel? {
        models.first { $0.profile == profile } ?? models.first
    }

    static func effort(for model: RecommendedModel, requested: String) -> String? {
        effort(supported: model.efforts, requested: requested)
    }

    static func effort(supported: [String], requested: String) -> String? {
        if supported.contains(requested) { return requested }
        return supported.contains("medium") ? "medium" : supported.first
    }

    static func decodeCodex(_ data: Data) throws -> [RecommendedModel] {
        struct Cache: Decodable {
            struct Entry: Decodable {
                struct Level: Decodable { let effort: String }
                let slug: String
                let display_name: String
                let visibility: String
                let priority: Int
                let supported_reasoning_levels: [Level]
            }
            let models: [Entry]
        }
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        var seen = Set<String>()
        return cache.models.filter { $0.visibility == "list" && seen.insert($0.slug).inserted }
            .sorted { $0.priority < $1.priority }.map {
                RecommendedModel(id: $0.slug, name: $0.display_name, host: .codex,
                                 profile: $0.slug.contains("luna") ? "fast" : $0.slug.contains("astra") ? "capable" : "balanced",
                                 efforts: $0.supported_reasoning_levels.map(\.effort))
            }
    }
}

actor CodexModelReader {
    func read() throws -> [RecommendedModel] {
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let path = root.appendingPathComponent("models_cache.json")
        let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 8_000_000 else { throw ClientError.message("Model catalog is too large.") }
        return try ModelRecommendation.decodeCodex(Data(contentsOf: path))
    }
}

@MainActor @Observable
final class ModelCatalog {
    private(set) var codexModels: [RecommendedModel] = []
    private(set) var error: String?
    func models(for host: HostApp) -> [RecommendedModel] {
        host == .cursor ? ModelRecommendation.cursorModels : codexModels
    }
    func refresh() async {
        do { codexModels = try await CodexModelReader().read(); error = nil }
        catch { self.error = "Open Codex to refresh its model catalog." }
    }
}
