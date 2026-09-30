import Foundation

/// A bounded snapshot of one chat. It is never persisted or merged across captures.
struct ConversationContext: Codable, Equatable, Sendable {
    struct Message: Codable, Equatable, Sendable {
        let role: String
        let content: String
    }
    let conversationId: String
    let source: String
    let messages: [Message]
    let truncated: Bool

    var text: String { messages.map(\.content).joined(separator: "\n\n") }

    static func snapshot(_ text: String, id: String, source: String, partial: Bool = false) -> Self? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // Count UTF-16 to agree with JavaScript; never cut a Unicode character.
        var kept: [Character] = [], size = 0
        for character in text.reversed() {
            let count = character.utf16.count
            if size + count > 24_000 { break }
            kept.append(character)
            size += count
        }
        var messages: [Message] = [], chunk = "", chunkSize = 0
        for character in kept.reversed() {
            let count = character.utf16.count
            if chunkSize + count > 8_000 {
                if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.append(Message(role: "context", content: chunk))
                }
                chunk = ""; chunkSize = 0
            }
            chunk.append(character); chunkSize += count
        }
        if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(Message(role: "context", content: chunk))
        }
        guard !messages.isEmpty else { return nil }
        return Self(conversationId: id, source: source, messages: messages,
                    truncated: partial || size < text.utf16.count)
    }
}

enum ChatContextPolicy {
    static func isConversation(role: String, label: String) -> Bool {
        guard ["AXGroup", "AXScrollArea", "AXWebArea"].contains(role), !excludes(role: role, label: label) else { return false }
        return label.range(of: #"\b(conversation|chat|messages|konverzace)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func excludes(role: String, label: String) -> Bool {
        if ["AXTextArea", "AXTextField", "AXComboBox", "AXOutline", "AXToolbar", "AXMenuBar", "AXWindow"].contains(role) { return true }
        return label.range(of: #"\b(sidebar|navigation|chat history|conversations|terminal|code editor|search|password)\b"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }
}
