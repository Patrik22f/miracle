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
/// clipboard access, window crawling, or prompt persistence are used.
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
        guard let current = elementAttribute(app, kAXFocusedUIElementAttribute), CFEqual(focused, current) else {
            return .status(.waiting)
        }
        return .captured(CapturedPrompt(text: captured.text, source: source, fieldID: fieldID,
                                        bounds: bounds, supportsAutomaticRecommendations: automatic))
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
