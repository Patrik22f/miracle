#if DEBUG
import Foundation

extension PromptSource {
    static let fixture = PromptSource(processID: 42, bundleIdentifier: "dev.preflight.fixture", name: "Test Editor")
}

actor CaptureReaderSpyingStub: FocusedTextReading {
    private(set) var calls = 0
    let reading: CaptureReading

    init(reading: CaptureReading = .captured(CapturedPrompt(text: "A test prompt", source: .fixture))) {
        self.reading = reading
    }

    func read(from source: PromptSource, mode: CaptureMode) -> CaptureReading {
        calls += 1
        return reading
    }
}

/// Explicit handshakes let race tests run without sleeps or timing assumptions.
actor DeferredValue<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func request() async -> Value {
        await withCheckedContinuation { continuation in
            precondition(self.continuation == nil)
            self.continuation = continuation
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resolve(_ value: Value) {
        precondition(continuation != nil)
        continuation?.resume(returning: value)
        continuation = nil
    }
}

struct DeferredCaptureReader: FocusedTextReading {
    let value: DeferredValue<CaptureReading>
    func read(from source: PromptSource, mode: CaptureMode) async -> CaptureReading {
        await value.request()
    }
}

@MainActor
final class CaptureEnvironmentStub {
    var trusted = true
    var source: PromptSource? = .fixture
    var environment: CaptureEnvironment {
        CaptureEnvironment(isTrusted: { self.trusted }, frontmostSource: { self.source }, ownProcessID: 100)
    }
}
extension CapturedPrompt {
    static func cursorFixture(text: String = "Optimize a SwiftUI app") -> CapturedPrompt {
        CapturedPrompt(text: text,
                       source: PromptSource(processID: 123, bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
                       fieldID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
                       bounds: CGRect(x: 0, y: 100, width: 500, height: 100),
                       supportsAutomaticRecommendations: true)
    }
}
#endif
