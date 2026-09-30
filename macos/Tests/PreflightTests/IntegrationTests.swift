import AppKit
import Testing
@testable import Preflight

@MainActor @Suite("Merged capture and presentation")
struct IntegrationTests {
    @Test("Recognized live prompts drive recommendations and moving the field preserves selection")
    func recognizedPrompt() async throws {
        let model = AppModel { _, _, _ in try .demo() }
        var captured = CapturedPrompt.cursorFixture()
        model.receiveCapture(.captured(captured))
        await model.task?.value
        let result = try #require(model.result)
        #expect(model.source == captured.source)
        #expect(model.selected == Set(result.skills.map(\.id)))
        #expect(model.hasUnreadRecommendation)

        model.selected = []
        model.markRead()
        captured.bounds = CGRect(x: 80, y: 120, width: 500, height: 100)
        model.receiveCapture(.captured(captured))

        #expect(model.activeSnapshot?.bounds == captured.bounds)
        #expect(model.result != nil)
        #expect(model.selected.isEmpty)
        #expect(!model.hasUnreadRecommendation)
    }

    @Test("Disabling automatic advice keeps live capture; re-enabling analyzes the current prompt")
    func automaticToggle() async {
        let model = AppModel { _, _, _ in try .demo() }
        model.setAutomaticRecommendationsEnabled(false)
        let captured = CapturedPrompt.cursorFixture()
        model.receiveCapture(.captured(captured))
        #expect(model.prompt == captured.text)
        #expect(model.liveCaptureEnabled)
        #expect(model.task == nil)

        model.setAutomaticRecommendationsEnabled(true)
        model.receiveCapture(.captured(captured))
        await model.task?.value
        #expect(model.result != nil)
        #expect(model.activeSnapshot != nil)
    }

    @Test("Leaving an automatic prompt cancels analysis and removes its anchor",
          arguments: [CaptureStatus.permissionRequired, .secureField("Cursor"), .unsupported("Cursor"),
                      .unreadable("Cursor"), .tooLong("Cursor"), .suspended, .waiting])
    func unavailableAutomaticPrompt(status: CaptureStatus) async {
        let model = AppModel { _, _, _ in try .demo() }
        model.receiveCapture(.captured(.cursorFixture()))
        let pending = model.task

        model.receiveCapture(.status(status))
        await pending?.value

        #expect(model.prompt.isEmpty)
        #expect(model.activeSnapshot == nil)
        #expect(model.result == nil)
        #expect(!model.isLoading)
        #expect(!model.hasUnreadRecommendation)
    }

    @Test("Pause and setup reject late automatic responses and samples",
          arguments: ["live", "automatic", "setup"])
    func lateAutomaticResponse(action: String) async throws {
        let deferred = DeferredValue<AnalyzeResponse>()
        let model = AppModel { _, _, _ in await deferred.request() }
        let captured = CapturedPrompt.cursorFixture()
        model.receiveCapture(.captured(captured))
        let pending = model.task
        await deferred.waitUntilRequested()

        switch action {
        case "live": model.setLiveCaptureEnabled(false)
        case "automatic": model.setAutomaticRecommendationsEnabled(false)
        default: model.setCaptureSuspended(true)
        }
        await deferred.resolve(try .demo())
        await pending?.value
        model.receiveCapture(.captured(captured))

        #expect(model.prompt == captured.text)
        #expect(model.activeSnapshot == nil)
        #expect(model.result == nil)
        #expect(!model.isLoading)
        #expect(!model.hasUnreadRecommendation)
    }

    @Test("The explicit shortcut still captures and analyzes while live capture is paused")
    func explicitCapture() async throws {
        let captured = CapturedPrompt.cursorFixture(text: "A selected excerpt")
        let reader = CaptureReaderSpyingStub(reading: .captured(captured))
        let environment = CaptureEnvironmentStub()
        environment.source = captured.source
        let monitor = LivePromptMonitor(reader: reader, environment: environment.environment)
        let model = AppModel(monitor: monitor) { _, _, _ in try .demo() }
        model.setLiveCaptureEnabled(false)

        await model.capture()
        await model.task?.value

        #expect(model.prompt == captured.text)
        #expect(model.source == captured.source)
        #expect(model.result != nil)
        #expect(!model.liveCaptureEnabled)
        #expect(model.activeSnapshot == nil)
        #expect(await reader.calls == 1)
    }

    @Test("A paused monitor refreshes permission without reading host text")
    func pausedPermissionRefresh() async {
        let reader = CaptureReaderSpyingStub()
        let environment = CaptureEnvironmentStub()
        let monitor = LivePromptMonitor(reader: reader, environment: environment.environment)
        var permission = false
        monitor.onPermission = { permission = $0 }
        monitor.isEnabled = { false }

        #expect(await monitor.sample() == .status(.reviewing))
        #expect(permission)
        #expect(await reader.calls == 0)
    }
}

@MainActor @Suite("Automatic recommendation regressions")
struct AutomaticRecommendationRegressionTests {
    @Test("Manual edits and pastes analyze the settled prompt without an Analyze click")
    func manualDebounce() async throws {
        let recorder = RecommendationRequestRecorder()
        let model = AppModel { text, host, context in try await recorder.analyze(text, host, context) }
        model.editPrompt("First draft")
        let first = model.task
        model.editPrompt("Pasted final draft")
        await first?.value
        await model.task?.value
        #expect(await recorder.prompts == ["Pasted final draft"])
        #expect(model.result != nil)
        #expect(!model.liveCaptureEnabled)
        model.editPrompt("")
        #expect(model.result == nil)
        #expect(!model.isLoading)
    }

    @Test("Captured host changes and manual context edits reanalyze with the correct host")
    func hostAndContext() async throws {
        let recorder = RecommendationRequestRecorder()
        let model = AppModel { text, host, context in try await recorder.analyze(text, host, context) }
        model.receiveCapture(.captured(.cursorFixture(text: "Continue")))
        await model.task?.value
        model.receiveCapture(.captured(.init(text: "Continue",
            source: .init(processID: 555, bundleIdentifier: "com.openai.codex", name: "Codex"),
            fieldID: UUID(), supportsAutomaticRecommendations: true)))
        model.editContext("Migrate Swift concurrency and actor isolation")
        await model.task?.value
        #expect(await recorder.hosts == ["Cursor", "Codex"])
        #expect(await recorder.contexts.last??.text == "Migrate Swift concurrency and actor isolation")
    }

    @Test("Pausing cancels a pending manual analysis and resume analyzes the existing draft")
    func pauseResume() async throws {
        let recorder = RecommendationRequestRecorder()
        let model = AppModel { text, host, context in try await recorder.analyze(text, host, context) }
        model.editPrompt("Analyze this draft")
        let pending = model.task
        model.setAutomaticRecommendationsEnabled(false)
        await pending?.value
        #expect(await recorder.prompts.isEmpty)
        #expect(!model.isLoading)
        model.setAutomaticRecommendationsEnabled(true)
        await model.task?.value
        #expect(await recorder.prompts == ["Analyze this draft"])
    }

    @Test("Switching hosts with the same prompt changes the request host")
    func switchHost() async throws {
        let recorder = RecommendationRequestRecorder()
        let model = AppModel { text, host, context in try await recorder.analyze(text, host, context) }
        var captured = CapturedPrompt.cursorFixture()
        model.receiveCapture(.captured(captured))
        await model.task?.value
        captured = CapturedPrompt(text: captured.text, source: .init(processID: 555, bundleIdentifier: "com.openai.codex", name: "Codex"),
                                  fieldID: UUID(), supportsAutomaticRecommendations: true)
        model.receiveCapture(.captured(captured))
        await model.task?.value
        #expect(model.targetApp == .codex)
        #expect(await recorder.hosts == ["Cursor", "Codex"])
    }
}

private actor RecommendationRequestRecorder {
    var prompts: [String] = []
    var hosts: [String?] = []
    var contexts: [ConversationContext?] = []
    func analyze(_ text: String, _ host: String?, _ context: ConversationContext?) throws -> AnalyzeResponse {
        prompts.append(text); hosts.append(host); contexts.append(context)
        return try .demo()
    }
}
