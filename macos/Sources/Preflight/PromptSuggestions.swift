import AppKit
import Observation

struct PromptSuggestion: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let reason: String
    let files: [String]
}

struct SuggestionResponse: Codable, Sendable {
    let schemaVersion: String
    let status: String
    let suggestions: [PromptSuggestion]
    let provider: String
    let model: String
    let retryAfterMs: Int
    var message: String? = nil
    var summary: String? = nil
    var project: Project? = nil
    var cached: Bool? = nil
    var generatedAt: String? = nil

    struct Project: Codable, Sendable {
        let name: String
        let path: String
        let revision: String
        let scannedAt: String
        let fileCount: Int
        let sampledFileCount: Int
        let partial: Bool
    }
}

struct SuggestionRequest: Codable, Sendable, Equatable {
    let projectPath: String
    let prompt: String
    let context: ConversationContext?
}

extension APIClient {
    func suggestions(_ input: SuggestionRequest) async throws -> SuggestionResponse {
        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent("suggestions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(input)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 422 {
                throw ClientError.message("Could not read this project. Choose an accessible folder.")
            }
            throw ClientError.message("Start the updated local backend to get prompt suggestions.")
        }
        let result = try JSONDecoder().decode(SuggestionResponse.self, from: data)
        guard result.schemaVersion == "1.0", ["ready", "setup", "waiting", "error", "empty"].contains(result.status),
              result.suggestions.count <= 3,
              result.status != "ready" || (result.suggestions.count == 3 && Set(result.suggestions.map(\.id)).count == 3) else {
            throw ClientError.message("Update Miracle and its backend together.")
        }
        return result
    }
}

@MainActor @Observable
final class PromptSuggestionsModel {
    private(set) var enabled: Bool
    private(set) var selectedProjectPath: String
    private(set) var detectedProjectPath: String?
    private(set) var response: SuggestionResponse?
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var copiedID: String?
    var projectPath: String { selectedProjectPath.isEmpty ? detectedProjectPath ?? "" : selectedProjectPath }
    var projectName: String { projectPath.isEmpty ? "Choose a project" : URL(fileURLWithPath: projectPath).lastPathComponent }
    @ObservationIgnored var changed: () -> Void = {}
    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let fetch: @Sendable (SuggestionRequest) async throws -> SuggestionResponse
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    private var current: SuggestionRequest?
    private var running = false
    private var revision = UUID()
    private var prompt = ""
    private var context: ConversationContext?

    init(preferences: UserDefaults? = nil,
         fetch: @escaping @Sendable (SuggestionRequest) async throws -> SuggestionResponse = { try await APIClient().suggestions($0) }) {
        self.preferences = preferences
        self.fetch = fetch
        enabled = preferences?.object(forKey: "promptSuggestionsEnabled") as? Bool ?? true
        selectedProjectPath = preferences?.string(forKey: "suggestionProjectPath") ?? ""
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        preferences?.set(enabled, forKey: "promptSuggestionsEnabled")
        restart()
    }

    func setRunning(_ running: Bool) {
        guard self.running != running else { return }
        self.running = running
        restart()
    }

    func selectProject(_ path: String) {
        selectedProjectPath = path
        preferences?.set(path, forKey: "suggestionProjectPath")
        restart()
    }

    func chooseProject() {
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = false
        chooser.prompt = "Use project"
        chooser.message = "Miracle will keep this project up to date and use code excerpts with Groq to suggest your next task."
        if chooser.runModal() == .OK, let url = chooser.url { selectProject(url.path) }
    }

    func update(prompt: String, context: ConversationContext?, detectedProjectPath: String?) {
        self.prompt = prompt
        self.context = context
        self.detectedProjectPath = detectedProjectPath
        let input = SuggestionRequest(projectPath: projectPath, prompt: prompt, context: context)
        guard input != current else { return }
        restart()
    }

    func refresh() { restart(immediate: true) }

    private func restart(immediate: Bool = false) {
        task?.cancel()
        task = nil
        revision = UUID()
        response = nil
        message = nil
        copiedID = nil
        isLoading = false
        let input = SuggestionRequest(projectPath: projectPath, prompt: prompt, context: context)
        current = input
        guard enabled, running, !projectPath.isEmpty else { changed(); return }
        let revision = revision
        let fetch = fetch
        isLoading = true
        changed()
        task = Task { [weak self] in
            do {
                if !immediate { try await Task.sleep(for: .milliseconds(1200)) }
                while !Task.isCancelled {
                    let delay: Int
                    do {
                        let result = try await fetch(input)
                        guard !Task.isCancelled, let self, self.revision == revision else { return }
                        self.response = result
                        self.message = result.message
                        self.isLoading = false
                        self.changed()
                        // Poll the local snapshot; unchanged content uses the backend cache.
                        delay = max(15000, min(300000, result.retryAfterMs))
                    } catch {
                        guard !Task.isCancelled, let self, self.revision == revision else { return }
                        self.response = nil
                        self.message = error.localizedDescription
                        self.isLoading = false
                        self.changed()
                        delay = 30000
                    }
                    try await Task.sleep(for: .milliseconds(delay))
                }
            } catch { /* Cancellation stops polling and prevents late UI updates. */ }
        }
    }

    func copy(_ suggestion: PromptSuggestion) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestion.prompt, forType: .string)
        copiedID = suggestion.id
    }
}

enum ProjectDirectory {
    /// Only use a local document explicitly exposed by the focused host window.
    /// Never guess from a window title or another chat's recent workspace.
    static func resolve(document: String?) -> String? {
        guard let document, let url = URL(string: document), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        var folder = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        var candidate: String?
        for _ in 0..<16 {
            guard folder.path != "/", folder.path != NSHomeDirectory() else { break }
            if manager.fileExists(atPath: folder.appendingPathComponent(".git").path) { return folder.path }
            if candidate == nil, ["Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "go.mod"].contains(where: {
                manager.fileExists(atPath: folder.appendingPathComponent($0).path)
            }) { candidate = folder.path }
            folder.deleteLastPathComponent()
        }
        return candidate
    }
}
