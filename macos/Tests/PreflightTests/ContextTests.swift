import Foundation
import Testing
@testable import Preflight

@Suite("Chat context contract")
struct ContextContractTests {
    @Test("Long Unicode context respects every API budget without splitting characters")
    func budgets() throws {
        let context = try #require(ConversationContext.snapshot(String(repeating: "😀é", count: 10_000), id: "chat", source: "manual"))
        #expect(context.truncated)
        #expect(context.messages.count <= 16)
        #expect(context.messages.allSatisfy { $0.content.utf16.count <= 8_000 })
        #expect(context.messages.reduce(0) { $0 + $1.content.utf16.count } <= 24_000)
        #expect(context.messages.allSatisfy { !$0.content.contains("�") })
        let request = AnalyzeRequest(prompt: "Continue.", app: "Cursor", context: context)
        let roundTrip = try JSONDecoder().decode(AnalyzeRequest.self, from: JSONEncoder().encode(request))
        #expect(roundTrip.context == context)
    }

    @Test("Chat extraction requires a labeled container and excludes other surfaces")
    func boundaries() {
        #expect(ChatContextPolicy.isConversation(role: "AXGroup", label: "Chat conversation"))
        #expect(!ChatContextPolicy.isConversation(role: "AXWindow", label: "Chat"))
        #expect(!ChatContextPolicy.isConversation(role: "AXGroup", label: "Chat history sidebar"))
        #expect(!ChatContextPolicy.isConversation(role: "AXGroup", label: "Editor"))
        #expect(ChatContextPolicy.excludes(role: "AXTextArea", label: "Prompt"))
        #expect(ChatContextPolicy.excludes(role: "AXGroup", label: "Terminal"))
    }
}

@MainActor @Suite("Chat context lifecycle")
struct ContextLifecycleTests {
    private let first = ConversationContext.snapshot("Swift concurrency migration", id: "first", source: "accessibility", partial: true)!
    private let second = ConversationContext.snapshot("React rendering performance", id: "second", source: "accessibility", partial: true)!

    @Test("Context travels with captured text to the analysis call, but never into copied prompt")
    func propagation() async throws {
        let recorder = ContextRecorder()
        let model = AppModel { text, _, context in try await recorder.analyze(text, context: context) }
        model.receiveCapture(.captured(CapturedPrompt(text: "Continue.", source: .fixture, context: first)))
        await model.analyze()?.value
        #expect(await recorder.contexts == [first])
        #expect(await recorder.prompts == ["Continue."])
        #expect(!model.promptWithSkills(includeSkills: true).contains("Swift concurrency migration"))
    }

    @Test("Same composer and prompt with a new chat snapshot triggers a new recommendation")
    func changedHistory() async {
        let recorder = ContextRecorder()
        let model = AppModel { text, _, context in try await recorder.analyze(text, context: context) }
        let field = UUID()
        let a = PromptSnapshot(text: "Continue.", appName: "Cursor", processID: 123, fieldID: field, bounds: nil, context: first)
        let b = PromptSnapshot(text: "Continue.", appName: "Cursor", processID: 123, fieldID: field, bounds: nil, context: second)
        model.receive(a)
        await model.task?.value
        model.receive(b)
        #expect(model.result == nil)
        await model.task?.value
        #expect(await recorder.contexts == [first, second])
        model.receive(b)
        #expect(await recorder.contexts.count == 2)
        model.receive(nil)
        #expect(model.context == nil)
        #expect(model.result == nil)
    }

    @Test("Context edit cancels an in-flight response and manual context resists late capture")
    func staleContext() async throws {
        let deferred = DeferredValue<AnalyzeResponse>()
        let model = AppModel { _, _, _ in await deferred.request() }
        model.receiveCapture(.captured(CapturedPrompt(text: "Continue.", source: .fixture, context: first)))
        let pending = try #require(model.analyze())
        await deferred.waitUntilRequested()
        model.editContext("Different task")
        model.receiveCapture(.captured(CapturedPrompt(text: "Late", source: .fixture, context: first)))
        await deferred.resolve(try .demo())
        await pending.value
        #expect(model.result == nil)
        #expect(model.context?.source == "manual")
        #expect(model.contextText == "Different task")
        #expect(!model.liveCaptureEnabled)
        model.editContext("")
        #expect(model.context == nil)
    }

    @Test("Capture without context clears the previous chat's context")
    func noContext() {
        let model = AppModel()
        model.receiveCapture(.captured(CapturedPrompt(text: "Continue.", source: .fixture, context: first)))
        model.receiveCapture(.captured(CapturedPrompt(text: "Continue.", source: .fixture)))
        #expect(model.context == nil)
    }
}

private actor ContextRecorder {
    var prompts: [String] = []
    var contexts: [ConversationContext?] = []
    func analyze(_ prompt: String, context: ConversationContext?) throws -> AnalyzeResponse {
        prompts.append(prompt)
        contexts.append(context)
        return try .demo()
    }
}
