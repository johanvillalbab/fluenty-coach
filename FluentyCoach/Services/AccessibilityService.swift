import AppKit
import ApplicationServices

@MainActor
final class AccessibilityService {

    /// Returns true if the app has been granted Accessibility permission.
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission if not already granted.
    /// Should be called once at launch.
    func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Capture the focused AXUIElement from the frontmost app.
    /// Must be called BEFORE showing the popover (while source app is still frontmost).
    func captureFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard result == .success, let element = focusedElement else { return nil }
        return (element as! AXUIElement) // swiftlint:disable:this force_cast
    }

    func captureSelectedRange(in element: AXUIElement) -> NSRange? {
        guard let range = selectedTextRange(in: element) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    /// Replace the selected text in the given element with newText.
    /// `completion` is called once the replacement is done (or immediately on failure).
    func replaceSelectedText(in element: AXUIElement, with newText: String, selectedRange: NSRange?, completion: @escaping @MainActor () -> Void) {
        // Strategy 1: Replace within the control's full value using the selected range.
        if replaceUsingValueAttribute(in: element, with: newText, selectedRange: selectedRange) {
            completion()
            return
        }

        // Strategy 2: Direct kAXSelectedTextAttribute write for controls that support it.
        let selectedTextWriteResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            newText as CFString
        )
        if selectedTextWriteResult == .success {
            completion()
            return
        }

        // Strategy 3: Clipboard + Cmd+V paste fallback
        pasteViaClipboard(
            with: newText,
            sourceElement: element,
            selectedRange: selectedRange,
            shouldRestoreSelection: true,
            completion: completion
        )
    }

    func pasteText(_ text: String, in element: AXUIElement, selectedRange: NSRange?, completion: @escaping @MainActor () -> Void) {
        pasteViaClipboard(
            with: text,
            sourceElement: element,
            selectedRange: selectedRange,
            shouldRestoreSelection: true,
            completion: completion
        )
    }

    func pasteCurrentClipboard(in element: AXUIElement, selectedRange: NSRange?, completion: @escaping @MainActor () -> Void) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else {
            completion()
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            completion()
            return
        }
        app.activate(options: .activateIgnoringOtherApps)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            self.restoreFocusAndSelection(in: element, selectedRange: selectedRange)

            try? await Task.sleep(for: .milliseconds(60))
            self.simulatePaste()

            try? await Task.sleep(for: .milliseconds(250))
            completion()
        }
    }

    func pasteText(_ text: String, inApplicationWithPID pid: pid_t, completion: @escaping @MainActor () -> Void) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            completion()
            return
        }
        app.activate(options: .activateIgnoringOtherApps)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if !self.pasteViaSystemEvents() {
                self.simulatePaste()
            }

            try? await Task.sleep(for: .milliseconds(200))
            completion()
        }
    }

    private func replaceUsingValueAttribute(in element: AXUIElement, with newText: String, selectedRange: NSRange?) -> Bool {
        guard let currentValue = stringAttribute(kAXValueAttribute, in: element),
              let selectedRange = selectedRange ?? captureSelectedRange(in: element) else {
            return false
        }

        let currentNSString = currentValue as NSString
        let validLocation = max(0, min(selectedRange.location, currentNSString.length))
        let maxLength = currentNSString.length - validLocation
        let validLength = max(0, min(selectedRange.length, maxLength))
        let safeRange = NSRange(location: validLocation, length: validLength)

        let replacedValue = currentNSString.replacingCharacters(in: safeRange, with: newText)
        let setValueResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            replacedValue as CFString
        )
        guard setValueResult == .success else {
            return false
        }

        let updatedCursorLocation = safeRange.location + (newText as NSString).length
        var updatedRange = CFRange(location: updatedCursorLocation, length: 0)
        if let updatedRangeValue = AXValueCreate(.cfRange, &updatedRange) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                updatedRangeValue
            )
        }

        return true
    }

    private func stringAttribute(_ attribute: String, in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }

        if let stringValue = value as? String {
            return stringValue
        }
        if let attributedStringValue = value as? NSAttributedString {
            return attributedStringValue.string
        }
        return nil
    }

    private func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success,
              let rangeValue = value,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = rangeValue as! AXValue // swiftlint:disable:this force_cast
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private func pasteViaClipboard(
        with text: String,
        sourceElement: AXUIElement,
        selectedRange: NSRange?,
        shouldRestoreSelection: Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        let pb = NSPasteboard.general
        let previousContents = pb.string(forType: .string)

        var pid: pid_t = 0
        guard AXUIElementGetPid(sourceElement, &pid) == .success, pid != 0 else {
            completion()
            return
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            completion()
            return
        }
        app.activate(options: .activateIgnoringOtherApps)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            self.restoreFocusAndSelection(
                in: sourceElement,
                selectedRange: shouldRestoreSelection ? selectedRange : nil
            )

            pb.clearContents()
            pb.setString(text, forType: .string)

            try? await Task.sleep(for: .milliseconds(60))
            self.simulatePaste()

            try? await Task.sleep(for: .milliseconds(250))
            completion()

            try? await Task.sleep(for: .milliseconds(650))
            if let prev = previousContents {
                pb.clearContents()
                pb.setString(prev, forType: .string)
            } else {
                pb.clearContents()
            }
        }
    }

    private func restoreFocusAndSelection(in element: AXUIElement, selectedRange: NSRange?) {
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success, pid != 0 {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                element
            )
        }

        AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )

        guard let selectedRange else { return }
        var range = CFRange(location: selectedRange.location, length: selectedRange.length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return }

        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
    }

    private func pasteViaSystemEvents() -> Bool {
        let source = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return false }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    /// Replace the active selection in the source app with translated text.
    /// Activates the source app via PID before pasting so the ⌘V goes to the right
    /// window (clicking the Replace button can momentarily make our panel the key window).
    func replaceSelection(in sourcePID: pid_t?, with text: String, completion: @escaping @MainActor () -> Void) {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        // Re-activate the source app so it owns key window status before we paste.
        if let pid = sourcePID, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

        Task { @MainActor in
            // Wait for activation to settle
            try? await Task.sleep(for: .milliseconds(120))
            self.simulatePaste()

            try? await Task.sleep(for: .milliseconds(200))
            completion()

            try? await Task.sleep(for: .milliseconds(600))
            pb.clearContents()
            if let prev = previous { pb.setString(prev, forType: .string) }
        }
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        // Use HID tap (system-wide, matches what Whisp uses) with a tiny gap between down/up
        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.04)
        keyUp?.post(tap: .cghidEventTap)
    }
}
