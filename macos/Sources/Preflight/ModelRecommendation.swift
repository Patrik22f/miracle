import Foundation
import Observation
import SQLite3

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
    var enabled = true
}

enum ModelRecommendation {
    // Manual fallback only. Live catalog entries and their declared efforts take precedence.
    static let cursorModels: [RecommendedModel] = [
        .init(id: "grok-4.6", name: "Grok 4.6", host: .cursor, profile: "balanced", efforts: ["low", "medium", "high", "xhigh"]),
        .init(id: "grok-4.7", name: "Grok 4.7", host: .cursor, profile: "capable", efforts: ["low", "medium", "high", "xhigh"]),
        .init(id: "composer-2.5", name: "Composer 2.5", host: .cursor, profile: "fast", efforts: []),
        .init(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", host: .cursor, profile: "capable", efforts: []),
        .init(id: "gpt-5.6-terra", name: "GPT-5.6 Terra", host: .cursor, profile: "balanced", efforts: []),
        .init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", host: .cursor, profile: "fast", efforts: [])
    ]
    static let effortOrder = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    static func normalizedEffort(_ value: String) -> String {
        ["extra-high", "extra_high"].contains(value) ? "xhigh" : value
    }

    static func choose(from models: [RecommendedModel], profile: String, requestedEffort: String = "medium") -> RecommendedModel? {
        let order = ["fast", "balanced", "capable"]
        let target = order.firstIndex(of: profile) ?? 1
        // Rank only host-available candidates. Capability fit first, then effort support,
        // then host catalog order (which puts preferred/current models first).
        return models.enumerated().min { lhs, rhs in
            func score(_ model: RecommendedModel) -> Int {
                let tier = order.firstIndex(of: model.profile) ?? 1
                let distance = abs(tier - target) * 100
                let underpowered = tier < target ? 20 : 0
                let effortMismatch = model.efforts.contains(requestedEffort) ? 0 : 5
                return distance + underpowered + effortMismatch + (model.id == "default" ? 10 : 0)
            }
            let a = score(lhs.element), b = score(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a < b
        }?.element
    }

    static func reason(for model: RecommendedModel, profile: String, availableCount: Int) -> String {
        let fit: String
        switch profile {
        case "fast": fit = "Prioritizes speed for a small, explicit task."
        case "capable": fit = "Prioritizes capability for complex or high-risk work."
        default: fit = "Balances speed and capability for implementation and investigation."
        }
        let availability = availableCount == 1 ? "Only one model is enabled for \(model.host.title)."
            : "Selected from \(availableCount) models enabled for \(model.host.title)."
        let fallback = model.profile != profile ? " Closest available capability tier." : ""
        return "\(fit) \(availability)\(fallback)"
    }

    static func effort(for model: RecommendedModel, requested: String) -> String? {
        effort(supported: model.efforts, requested: requested)
    }

    static func effort(supported: [String], requested: String) -> String? {
        if let exact = supported.first(where: { normalizedEffort($0) == normalizedEffort(requested) }) { return exact }
        guard let target = effortOrder.firstIndex(of: normalizedEffort(requested)) else { return supported.first }
        // Choose the nearest supported level, preferring more reasoning on ties.
        return supported.filter { effortOrder.contains(normalizedEffort($0)) }.min {
            let a = effortOrder.firstIndex(of: normalizedEffort($0))!, b = effortOrder.firstIndex(of: normalizedEffort($1))!
            return abs(a - target) == abs(b - target) ? a > b : abs(a - target) < abs(b - target)
        }
    }

    static func profile(id: String, description: String = "", host: HostApp) -> String {
        let text = "\(id) \(description)".lowercased()
        if ["luna", "mini", "nano", "flash", "haiku", "composer", "fast and", "fast responses"].contains(where: text.contains) { return "fast" }
        if ["astra", "opus", "fable", "frontier", "most demanding", "grok-4.7"].contains(where: text.contains)
            || (host == .cursor && id.contains("-sol")) { return "capable" }
        return "balanced"
    }

    static func decodeCodex(_ data: Data) throws -> [RecommendedModel] {
        struct Cache: Decodable {
            struct Entry: Decodable {
                struct Level: Decodable { let effort: String }
                let slug: String
                let display_name: String
                let visibility: String
                let priority: Int
                let description: String?
                let supported_reasoning_levels: [Level]
            }
            let models: [Entry]
        }
        let cache = try JSONDecoder().decode(Cache.self, from: data)
        var seen = Set<String>()
        return cache.models.filter { $0.visibility == "list" && seen.insert($0.slug).inserted }
            .sorted { $0.priority < $1.priority }.map {
                RecommendedModel(id: $0.slug, name: $0.display_name, host: .codex,
                                 profile: profile(id: $0.slug, description: $0.description ?? "", host: .codex),
                                 efforts: $0.supported_reasoning_levels.map(\.effort))
            }
    }

    static func decodeCursor(_ data: Data) throws -> [RecommendedModel] {
        guard let cache = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = cache["models"] as? [[String: Any]] else {
            throw ClientError.message("Cursor’s model catalog format is unavailable.")
        }
        let enabled = Set(cache["enabled"] as? [String] ?? [])
        let disabled = Set(cache["disabled"] as? [String] ?? [])
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let id = entry["name"] as? String, !id.isEmpty,
                  entry["supportsAgent"] as? Bool == true,
                  entry["isHidden"] as? Bool != true, entry["isDisabled"] as? Bool != true,
                  seen.insert(id).inserted else { return nil }
            let definitions = entry["parameterDefinitions"] as? [[String: Any]] ?? []
            let efforts = definitions.filter { ["effort", "reasoning", "reasoning_effort"].contains($0["id"] as? String ?? "") }
                .flatMap { definition -> [String] in
                    let type = definition["parameterType"] as? [String: Any]
                    let parameter = type?["enumParameter"] as? [String: Any]
                    return (parameter?["values"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }
                        .filter { effortOrder.contains(normalizedEffort($0)) }
                }
            return RecommendedModel(id: id, name: entry["clientDisplayName"] as? String ?? id, host: .cursor,
                                    profile: profile(id: id, host: .cursor), efforts: efforts,
                                    enabled: !disabled.contains(id) && (enabled.contains(id) || entry["defaultOn"] as? Bool == true))
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

actor CursorModelReader {
    func read(path: URL? = nil) throws -> [RecommendedModel] {
        let url = path ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw ClientError.message("Open Cursor to load its model catalog.")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        // Extract only model metadata. No chat history, credentials or other settings
        // leave SQLite, and the host database is never changed.
        let sql = """
        SELECT json_object('models', json_extract(value, '$.availableDefaultModels2'),
          'enabled', json_extract(value, '$.aiSettings.modelOverrideEnabled'),
          'disabled', json_extract(value, '$.aiSettings.modelOverrideDisabled'))
        FROM ItemTable WHERE key = 'src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser'
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ClientError.message("Cursor’s model catalog could not be read.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else {
            throw ClientError.message("Open Cursor to refresh its model catalog.")
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count < 8_000_000 else { throw ClientError.message("Model catalog is too large.") }
        return try ModelRecommendation.decodeCursor(Data(bytes: bytes, count: count))
    }
}

@MainActor @Observable
final class ModelCatalog {
    private(set) var codexModels: [RecommendedModel] = []
    private(set) var cursorModels: [RecommendedModel] = []
    private(set) var error: String?
    private(set) var cursorError: String?
    private(set) var cursorDetected = false
    private var refreshing = false
    private var refreshedAt = Date.distantPast
    var needsRefresh: Bool { !refreshing && Date().timeIntervalSince(refreshedAt) > 30 }
    func models(for host: HostApp) -> [RecommendedModel] {
        host == .cursor ? (cursorDetected ? cursorModels : ModelRecommendation.cursorModels) : codexModels
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        refreshedAt = Date()
        defer { refreshing = false }
        do { codexModels = try await CodexModelReader().read(); error = nil }
        catch { codexModels = []; self.error = "Open Codex to refresh its model catalog." }
        do { cursorModels = try await CursorModelReader().read(); cursorDetected = true; cursorError = nil }
        catch {
            cursorModels = []; cursorDetected = false
            cursorError = "Could not read Cursor’s local catalog. Select available models manually."
        }
    }
}
