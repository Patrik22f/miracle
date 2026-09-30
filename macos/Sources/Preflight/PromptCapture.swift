import Foundation

struct PromptSource: Equatable, Sendable {
    let processID: Int32
    let bundleIdentifier: String?
    let name: String
}

struct CapturedPrompt: Equatable, Sendable {
    let text: String
    let source: PromptSource
}

enum CaptureMode: Sendable {
    case live
    case selectionPreferred
}

enum CaptureStatus: Equatable, Sendable {
    case paused
    case permissionRequired
    case waiting
    case reviewing
    case following(String)
    case unsupported(String)
    case secureField(String)
    case unreadable(String)
    case tooLong(String)
    case suspended

    var description: String {
        switch self {
        case .paused: "Live capture paused. Your prompt stays here."
        case .permissionRequired: "Allow Accessibility to follow text in other apps."
        case .waiting: "Click a text field in another app to start."
        case .reviewing: "Ready. Switch to another app to keep following your prompt."
        case .following(let app): "Following the focused text field in \(app)."
        case .unsupported(let app): "Focus a supported text field in \(app), or paste here."
        case .secureField: "Password fields are excluded from capture."
        case .unreadable(let app): "\(app) isn’t sharing this field’s text. Copy and paste it here."
        case .tooLong: "This field exceeds 12,000 characters. Select less and press ⌥⌘Return."
        case .suspended: "Live capture waits while your Mac session is inactive."
        }
    }

    var symbol: String {
        switch self {
        case .following: "dot.radiowaves.left.and.right"
        case .paused, .suspended: "pause.circle"
        case .permissionRequired, .secureField: "lock"
        case .unsupported, .unreadable, .tooLong: "info.circle"
        case .waiting, .reviewing: "text.cursor"
        }
    }
}

enum CaptureReading: Equatable, Sendable {
    case captured(CapturedPrompt)
    case status(CaptureStatus)

    var status: CaptureStatus {
        switch self {
        case .captured(let prompt): .following(prompt.source.name)
        case .status(let status): status
        }
    }
}

/// Pure text policy shared by live capture and the explicit selection shortcut.
enum PromptTextPolicy {
    static let maximumLength = 12_000

    static func reading(fullText: String?, selectedText: String?, mode: CaptureMode, source: PromptSource) -> CaptureReading {
        let text: String?
        switch mode {
        case .live: text = fullText
        case .selectionPreferred: text = selectedText?.isEmpty == false ? selectedText : fullText
        }
        guard let text else { return .status(.unreadable(source.name)) }
        guard text.utf16.count <= maximumLength else { return .status(.tooLong(source.name)) }
        // Empty strings are real edits. Preserve whitespace, code indentation and newlines.
        return .captured(CapturedPrompt(text: text, source: source))
    }
}

protocol FocusedTextReading: Sendable {
    func read(from source: PromptSource, mode: CaptureMode) async -> CaptureReading
}
