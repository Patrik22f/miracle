import Foundation
import Testing
@testable import Preflight

@Suite("Prompt text policy")
struct PromptTextPolicyTests {
    @Test("Live capture preserves the whole field, indentation and trailing newlines")
    func fullField() {
        let text = "  func example() {\n    print(\"hello\")\n  }\n"
        let reading = PromptTextPolicy.reading(fullText: text, selectedText: "hello", mode: .live, source: .fixture)
        #expect(reading == .captured(CapturedPrompt(text: text, source: .fixture)))
    }

    @Test("The shortcut prefers an explicit selection even in an oversized document")
    func selection() {
        let reading = PromptTextPolicy.reading(fullText: String(repeating: "x", count: 12_001), selectedText: "excerpt", mode: .selectionPreferred, source: .fixture)
        #expect(reading == .captured(CapturedPrompt(text: "excerpt", source: .fixture)))
    }

    @Test("Empty fields are distinct from unreadable fields")
    func emptyAndUnavailable() {
        #expect(PromptTextPolicy.reading(fullText: "", selectedText: nil, mode: .live, source: .fixture) == .captured(CapturedPrompt(text: "", source: .fixture)))
        #expect(PromptTextPolicy.reading(fullText: nil, selectedText: "partial", mode: .live, source: .fixture) == .status(.unreadable("Test Editor")))
    }

    @Test("UTF-16 size limits agree with the JavaScript API", arguments: ["x", "😀"])
    func sizeLimit(character: String) {
        let text = String(repeating: character, count: 12_000 / character.utf16.count)
        #expect(PromptTextPolicy.reading(fullText: text, selectedText: nil, mode: .live, source: .fixture) == .captured(CapturedPrompt(text: text, source: .fixture)))
        #expect(PromptTextPolicy.reading(fullText: text + character, selectedText: nil, mode: .live, source: .fixture) == .status(.tooLong("Test Editor")))
    }
}

@MainActor @Suite("Live prompt state")
struct LivePromptStateTests {
    @Test("Live text reaches the prompt without starting analysis")
    func liveUpdate() {
        let model = AppModel()
        model.receiveCapture(.captured(CapturedPrompt(text: "Build a macOS app", source: .fixture)))
        #expect(model.prompt == "Build a macOS app")
        #expect(model.sourceApp == "Test Editor")
        #expect(model.captureStatus == .following("Test Editor"))
        #expect(!model.isLoading)
        #expect(model.result == nil)
    }

    @Test("Repeated samples preserve recommendations; changed and empty fields invalidate them")
    func changesAndDuplicates() throws {
        let model = AppModel()
        let reading = CaptureReading.captured(CapturedPrompt(text: "First prompt", source: .fixture))
        model.receiveCapture(reading)
        model.result = try .demo()
        model.selected = ["selected-skill"]
        model.receiveCapture(reading)
        #expect(model.result != nil)
        #expect(model.selected == ["selected-skill"])

        model.receiveCapture(.captured(CapturedPrompt(text: "", source: .fixture)))
        #expect(model.prompt.isEmpty)
        #expect(model.result == nil)
        #expect(model.selected.isEmpty)
    }

    @Test("The same text from another application updates provenance and invalidates results")
    func switchesApplications() throws {
        let model = AppModel()
        model.receiveCapture(.captured(CapturedPrompt(text: "Same text", source: .fixture)))
        model.result = try .demo()
        let second = PromptSource(processID: 43, bundleIdentifier: "dev.preflight.second", name: "Another Editor")
        model.receiveCapture(.captured(CapturedPrompt(text: "Same text", source: second)))
        #expect(model.source == second)
        #expect(model.result == nil)
    }

    @Test("Manual edits pause capture and cannot be overwritten by a late sample")
    func manualEditing() {
        let model = AppModel()
        model.receiveCapture(.captured(CapturedPrompt(text: "Captured", source: .fixture)))
        model.editPrompt("My manual draft")
        model.receiveCapture(.captured(CapturedPrompt(text: "Late sample", source: .fixture)))
        #expect(model.prompt == "My manual draft")
        #expect(model.source == nil)
        #expect(!model.liveCaptureEnabled)
        #expect(model.captureStatus == .paused)
    }

    @Test("Demo and paused states reject live data; resuming follows new data")
    func pauseDemoResume() {
        let model = AppModel()
        model.setLiveCaptureEnabled(false)
        model.receiveCapture(.captured(CapturedPrompt(text: "Ignored", source: .fixture)))
        #expect(model.prompt.isEmpty)
        model.setLiveCaptureEnabled(true)
        model.setDemoMode(true)
        model.receiveCapture(.captured(CapturedPrompt(text: "Ignored in demo", source: .fixture)))
        #expect(model.prompt.isEmpty)
        model.setDemoMode(false)
        model.receiveCapture(.captured(CapturedPrompt(text: "Resumed", source: .fixture)))
        #expect(model.prompt == "Resumed")
    }

    @Test("Unavailable input keeps the last snapshot with an honest capture status",
          arguments: [CaptureStatus.permissionRequired, .secureField("Editor"), .unsupported("Editor"), .unreadable("Editor"), .tooLong("Editor"), .reviewing])
    func unavailable(status: CaptureStatus) {
        let model = AppModel()
        model.receiveCapture(.captured(CapturedPrompt(text: "Last captured prompt", source: .fixture)))
        model.receiveCapture(.status(status))
        #expect(model.prompt == "Last captured prompt")
        #expect(model.captureStatus == status)
    }

    @Test("An analysis response for an older prompt cannot appear after a live edit")
    func staleAnalysis() async throws {
        let response = try AnalyzeResponse.demo()
        let deferred = DeferredValue<AnalyzeResponse>()
        let model = AppModel(analyzePrompt: { _, _ in await deferred.request() })
        model.receiveCapture(.captured(CapturedPrompt(text: "Original", source: .fixture)))
        let analysis = try #require(model.analyze())
        await deferred.waitUntilRequested()
        model.receiveCapture(.captured(CapturedPrompt(text: "New prompt", source: .fixture)))
        await deferred.resolve(response)
        await analysis.value
        #expect(model.prompt == "New prompt")
        #expect(model.result == nil)
        #expect(!model.isLoading)
    }
}

@MainActor @Suite("Capture lifecycle")
struct CaptureLifecycleTests {
    @Test("Permission denial and our own process never read external text")
    func permissionAndSelfExclusion() async {
        let reader = CaptureReaderSpyingStub()
        let environment = CaptureEnvironmentStub()
        let monitor = LivePromptMonitor(reader: reader, environment: environment.environment)
        environment.trusted = false
        #expect(await monitor.sample() == .status(.permissionRequired))
        environment.trusted = true
        environment.source = PromptSource(processID: 100, bundleIdentifier: "dev.preflight", name: "Preflight")
        #expect(await monitor.sample() == .status(.reviewing))
        #expect(await reader.calls == 0)
    }

    @Test("Granting permission is picked up without relaunching")
    func permissionRecovery() async {
        let reader = CaptureReaderSpyingStub()
        let environment = CaptureEnvironmentStub()
        let monitor = LivePromptMonitor(reader: reader, environment: environment.environment)
        environment.trusted = false
        #expect(await monitor.sample() == .status(.permissionRequired))
        environment.trusted = true
        #expect(await monitor.sample() == .captured(CapturedPrompt(text: "A test prompt", source: .fixture)))
        #expect(await reader.calls == 1)
    }

    @Test("App switches, permission revocation and stop discard in-flight reads", arguments: ["switch", "revoke", "stop"])
    func staleCapture(action: String) async {
        let deferred = DeferredValue<CaptureReading>()
        let environment = CaptureEnvironmentStub()
        let monitor = LivePromptMonitor(reader: DeferredCaptureReader(value: deferred), environment: environment.environment)
        let sample = Task { await monitor.sample() }
        await deferred.waitUntilRequested()
        switch action {
        case "switch": environment.source = nil
        case "revoke": environment.trusted = false
        default: monitor.stop()
        }
        await deferred.resolve(.captured(CapturedPrompt(text: "Obsolete prompt", source: .fixture)))
        let reading = await sample.value
        #expect(reading == .status(action == "revoke" ? .permissionRequired : .waiting))
    }
}
