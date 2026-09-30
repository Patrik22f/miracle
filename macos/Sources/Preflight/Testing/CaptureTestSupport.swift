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
#endif
