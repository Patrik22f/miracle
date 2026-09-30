import Foundation
import Testing
@testable import Preflight

private let exampleSuggestion = PromptSuggestion(id: "task", title: "Save tasks", prompt: "Persist tasks and verify that they survive relaunch.", reason: "Tasks are currently held in memory.", files: ["src/tasks.ts"])

private func suggestionResult() -> SuggestionResponse {
    SuggestionResponse(schemaVersion: "1.0", status: "ready", suggestions: [exampleSuggestion], provider: "groq", model: "test", retryAfterMs: 0)
}

@MainActor @Suite("Prompt suggestions")
struct PromptSuggestionTests {
    @Test("The shared suggestion response decodes in the native client")
    func sharedContract() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/suggestions-response.json"))
        let response = try JSONDecoder().decode(SuggestionResponse.self, from: data)
        #expect(response.status == "ready")
        #expect(response.suggestions.count == 3)
        #expect(response.project?.sampledFileCount == 4)
        #expect(response.suggestions.allSatisfy { !$0.files.isEmpty })
    }

    @Test("Opt-in live loopback response decodes through APIClient")
    func liveContract() async throws {
        guard let path = ProcessInfo.processInfo.environment["ZAZRAK_LIVE_PROJECT"] else { return }
        let response = try await APIClient().suggestions(SuggestionRequest(projectPath: path, prompt: "", context: nil))
        #expect(response.status == "ready")
        #expect(response.suggestions.count == 3)
        #expect(response.project?.path == path)
    }
    @Test("Project selection and opt-out survive relaunch")
    func preferences() throws {
        let name = "suggestions-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = PromptSuggestionsModel(preferences: defaults)
        model.selectProject("/project")
        model.setEnabled(false)
        let restored = PromptSuggestionsModel(preferences: defaults)
        #expect(restored.projectPath == "/project")
        #expect(!restored.enabled)
        #expect(restored.task == nil)
    }

    @Test("A response from a previous project is discarded even if cancellation is ignored")
    func staleProject() async {
        let deferred = DeferredValue<SuggestionResponse>()
        let model = PromptSuggestionsModel { _ in await deferred.request() }
        model.selectProject("/first")
        model.setRunning(true)
        model.refresh()
        let task = model.task
        await deferred.waitUntilRequested()
        model.selectProject("/second")
        await deferred.resolve(suggestionResult())
        await task?.value
        #expect(model.projectPath == "/second")
        #expect(model.response == nil)
        model.setRunning(false)
    }

    @Test("Demo suggestions need no project, enabled preference or backend")
    func demoSuggestions() throws {
        let name = "demo-suggestions-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "promptSuggestionsEnabled")
        let model = PromptSuggestionsModel(preferences: defaults) { _ in
            Issue.record("Demo suggestions must stay offline")
            throw ClientError.message("Unexpected API call")
        }
        model.setRunning(true)
        model.setDemoMode(true)
        #expect(model.projectPath.isEmpty)
        #expect(model.response?.suggestions.map(\.prompt) == DemoCatalog.scenarios.map(\.prompt))
        model.refresh()
        model.update(prompt: "A draft in Cursor", context: nil, detectedProjectPath: "/detected")
        #expect(model.response?.status == "ready")
        #expect(model.response?.project == nil)
        #expect(model.task == nil)
        #expect(!model.isLoading)
        model.setDemoMode(false)
        #expect(model.response == nil)
        #expect(!model.enabled)
        #expect(model.projectPath == "/detected")
        #expect(defaults.object(forKey: "suggestionProjectPath") == nil)
        #expect(!defaults.bool(forKey: "promptSuggestionsEnabled"))
    }

    @Test("Entering demo discards late suggestions and exit resumes live suggestions")
    func demoCancelsLiveRequest() async {
        let deferred = DeferredValue<SuggestionResponse>()
        let model = PromptSuggestionsModel { _ in await deferred.request() }
        model.selectProject("/project")
        model.setRunning(true)
        model.refresh()
        let pending = model.task
        await deferred.waitUntilRequested()
        model.setDemoMode(true)
        await deferred.resolve(suggestionResult())
        await pending?.value
        #expect(model.response?.suggestions.map(\.prompt) == DemoCatalog.scenarios.map(\.prompt))
        #expect(model.task == nil)
        model.setDemoMode(false)
        #expect(model.response == nil)
        #expect(model.projectPath == "/project")
        #expect(model.isLoading)
        #expect(model.task != nil)
        model.setRunning(false)
    }

    @Test("Opt-out, suspension and changed chat discard in-flight results", arguments: ["disable", "pause", "chat"])
    func cancellation(action: String) async {
        let deferred = DeferredValue<SuggestionResponse>()
        let model = PromptSuggestionsModel { _ in await deferred.request() }
        model.selectProject("/project")
        model.setRunning(true)
        model.refresh()
        let task = model.task
        await deferred.waitUntilRequested()
        switch action {
        case "disable": model.setEnabled(false)
        case "pause": model.setRunning(false)
        default: model.update(prompt: "New task", context: nil, detectedProjectPath: nil)
        }
        await deferred.resolve(suggestionResult())
        await task?.value
        #expect(model.response == nil)
        model.setRunning(false)
    }

    @Test("Selected folder overrides detection; follow-active clears the override")
    func projectPriority() {
        let model = PromptSuggestionsModel()
        model.update(prompt: "", context: nil, detectedProjectPath: "/detected")
        #expect(model.projectPath == "/detected")
        model.selectProject("/selected")
        model.update(prompt: "next", context: nil, detectedProjectPath: "/other")
        #expect(model.projectPath == "/selected")
        model.selectProject("")
        #expect(model.projectPath == "/other")
        model.update(prompt: "", context: nil, detectedProjectPath: nil)
        #expect(model.projectPath.isEmpty)
    }

    @Test("Using a suggested draft pauses capture and starts skill analysis")
    func useDraft() async {
        let model = AppModel { _, _, _ in try .demo() }
        model.useSuggestion(exampleSuggestion)
        #expect(model.prompt == exampleSuggestion.prompt)
        #expect(!model.liveCaptureEnabled)
        await model.task?.value
        #expect(model.result != nil)
    }

    @Test("A suggested draft keeps the detected host until live capture resumes")
    func draftHost() async {
        let model = AppModel { _, _, _ in try .demo() }
        model.receiveCapture(.captured(.cursorFixture()))

        model.useSuggestion(exampleSuggestion)
        await model.task?.value

        #expect(model.targetApp == .cursor)
        #expect(model.source == nil)
        #expect(model.activeSnapshot == nil)
        #expect(model.result != nil)

        model.setLiveCaptureEnabled(true)
        model.receiveCapture(.captured(.init(text: "Unrelated field", source: .fixture)))
        #expect(model.targetApp == nil)
        #expect(model.result == nil)
    }

    @Test("Local document detection finds the repository and rejects remote URLs")
    func documentDetection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("main.swift")
        try "print(1)".write(to: file, atomically: true, encoding: .utf8)
        #expect(ProjectDirectory.resolve(document: file.absoluteString) == root.path)
        #expect(ProjectDirectory.resolve(document: "https://example.com/main.swift") == nil)
        #expect(ProjectDirectory.resolve(document: "file://remote-host/tmp/main.swift") == nil)
        #expect(ProjectDirectory.resolve(document: nil) == nil)
    }
}
