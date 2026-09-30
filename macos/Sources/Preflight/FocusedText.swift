import AppKit
import ApplicationServices

@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static func request() {
        // Documented option key; avoid the legacy mutable C global under Swift 6.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// All synchronous cross-process AX reads stay off the UI actor. No key taps,
/// clipboard access, whole-window crawling, or prompt persistence are used.
actor FocusedTextReader: FocusedTextReading {
    private var preparedSource: PromptSource?
    private var previousElement: AXUIElement?
    private var fieldID = UUID()

    func read(from source: PromptSource, mode: CaptureMode) -> CaptureReading {
        guard !Task.isCancelled else { return .status(.waiting) }
        let app = AXUIElementCreateApplication(source.processID)
        AXUIElementSetMessagingTimeout(app, 0.15)
        if preparedSource != source {
            // Electron does not always build its text accessibility tree until
            // assistive software explicitly requests it. This documented knob
            // is ignored by apps that do not support it. It does not change focus.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            preparedSource = source
        }
        guard let focused = elementAttribute(app, kAXFocusedUIElementAttribute) else {
            return .status(.unsupported(source.name))
        }
        AXUIElementSetMessagingTimeout(focused, 0.15)
        guard let role = attribute(focused, kAXRoleAttribute) as? String else {
            return .status(.unreadable(source.name))
        }
        let subrole = attribute(focused, kAXSubroleAttribute) as? String
        guard subrole != kAXSecureTextFieldSubrole else { return .status(.secureField(source.name)) }
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            return .status(.unsupported(source.name))
        }
        var valueIsSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &valueIsSettable)
        guard valueIsSettable.boolValue || attribute(focused, "AXEditable") as? Bool == true else {
            return .status(.unsupported(source.name))
        }
        // Some web controls expose password semantics on a containing element.
        var parent = elementAttribute(focused, kAXParentAttribute)
        for _ in 0..<3 {
            guard let ancestor = parent else { break }
            AXUIElementSetMessagingTimeout(ancestor, 0.15)
            if attribute(ancestor, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
                return .status(.secureField(source.name))
            }
            parent = elementAttribute(ancestor, kAXParentAttribute)
        }
        guard !Task.isCancelled else { return .status(.waiting) }
        let selected = mode == .selectionPreferred ? attribute(focused, kAXSelectedTextAttribute) as? String : nil
        let hasSelection = selected?.isEmpty == false
        if !hasSelection, let count = attribute(focused, kAXNumberOfCharactersAttribute) as? NSNumber,
           count.intValue > PromptTextPolicy.maximumLength {
            return .status(.tooLong(source.name))
        }
        let full = hasSelection ? nil : attribute(focused, kAXValueAttribute) as? String
        // Do not deliver text read from a field that lost focus during the AX calls.
        guard let current = elementAttribute(app, kAXFocusedUIElementAttribute), CFEqual(focused, current) else {
            return .status(.waiting)
        }
        let reading = PromptTextPolicy.reading(fullText: full, selectedText: selected, mode: mode, source: source)
        guard case .captured(let captured) = reading else { return reading }
        if previousElement == nil || !CFEqual(previousElement, focused) {
            previousElement = focused
            fieldID = UUID()
        }
        let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute]
            .compactMap { attribute(focused, $0) as? String }.joined(separator: " ")
        let automatic = PromptPolicy.accepts(bundleID: source.bundleIdentifier ?? "", role: role,
                                             subrole: subrole ?? "", label: label)
        let bounds = fieldBounds(focused)
        let context = automatic ? conversationContext(around: focused, source: source) : nil
        let window = automatic ? elementAttribute(app, kAXFocusedWindowAttribute) : nil
        let projectPath = ProjectDirectory.resolve(document: window.flatMap { attribute($0, kAXDocumentAttribute) as? String })
        guard let current = elementAttribute(app, kAXFocusedUIElementAttribute), CFEqual(focused, current) else {
            return .status(.waiting)
        }
        return .captured(CapturedPrompt(text: captured.text, source: source, fieldID: fieldID,
                                        bounds: bounds, supportsAutomaticRecommendations: automatic, context: context, projectPath: projectPath))
    }

    private func conversationContext(around focused: AXUIElement, source: PromptSource) -> ConversationContext? {
        // Only inspect a labeled chat ancestor of a recognized composer. Never
        // fall back to the application/window or remember another chat's text.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(150))
        var ancestor = elementAttribute(focused, kAXParentAttribute)
        for _ in 0..<7 {
            guard let element = ancestor, !Task.isCancelled, ContinuousClock.now < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.01)
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if role == kAXWindowRole || role == kAXApplicationRole { return nil }
            let label = contextLabel(element)
            if ChatContextPolicy.isConversation(role: role, label: label) {
                var pending: [(AXUIElement, Int)] = [(element, 0)]
                var visited = 0, fragments: [String] = [], size = 0
                while let (node, depth) = pending.popLast(), visited < 240, ContinuousClock.now < deadline, !Task.isCancelled {
                    visited += 1
                    AXUIElementSetMessagingTimeout(node, 0.01)
                    let nodeRole = attribute(node, kAXRoleAttribute) as? String ?? ""
                    if CFEqual(node, focused) || attribute(node, "AXHidden") as? Bool == true
                        || ChatContextPolicy.excludes(role: nodeRole, label: contextLabel(node)) { continue }
                    if nodeRole == kAXStaticTextRole {
                        let value = attribute(node, kAXValueAttribute) as? String ?? attribute(node, kAXTitleAttribute) as? String ?? ""
                        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // Bound intermediate memory too, while keeping recent text.
                            let fragment = String(value.suffix(24_000))
                            fragments.insert(fragment, at: 0); size += fragment.utf16.count
                            while size > 32_000, fragments.count > 1 { size -= fragments.removeFirst().utf16.count }
                        }
                    } else if depth < 10, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                        // Visit recent messages first, then restore display order.
                        pending.append(contentsOf: children.suffix(240).map { ($0, depth + 1) })
                    }
                }
                return ConversationContext.snapshot(fragments.joined(separator: "\n\n"),
                    id: "ax-\(source.processID)-\(fieldID)", source: "accessibility", partial: true)
            }
            ancestor = elementAttribute(element, kAXParentAttribute)
        }
        return nil
    }

    private func contextLabel(_ element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute]
            .compactMap { attribute(element, $0) as? String }.joined(separator: " ")
    }

    private func fieldBounds(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = attribute(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
