import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyService: HotkeyService!
    private var translationService: TranslationService!
    private var accessibilityService: AccessibilityService!
    private var popoverController: PopoverController!
    private var translationState: TranslationState!
    private var settingsWindow: NSWindow?
    private var accessibilityPermissionRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        translationState = TranslationState()
        accessibilityService = AccessibilityService()
        translationService = TranslationService(state: translationState)
        popoverController = PopoverController(
            state: translationState,
            translation: translationService,
            accessibility: accessibilityService
        )

        hotkeyService = HotkeyService { [weak self] in
            self?.handleDoubleCopy()
        }
        hotkeyService.start()
    }

    // MARK: - Double Copy Handler

    private func handleDoubleCopy() {
        let cursorPos = NSEvent.mouseLocation

        // Request permission once on first use; never spam on repeated hotkey presses
        if !accessibilityService.isAccessibilityTrusted && !accessibilityPermissionRequested {
            accessibilityPermissionRequested = true
            accessibilityService.requestAccessibilityPermissionIfNeeded()
        }

        // Always capture the source app PID — works without accessibility permission
        translationState.sourceAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Capture focused element + selection range (requires accessibility — for precise AX replace)
        let focusedElement = accessibilityService.captureFocusedElement()
        translationState.sourceElement = focusedElement
        translationState.sourceSelectionRange = focusedElement.flatMap {
            accessibilityService.captureSelectedRange(in: $0)
        }

        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        guard !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard UserDefaults.standard.string(forKey: "deeplApiKey")?.isEmpty == false else {
            popoverController.showApiKeySetup(near: cursorPos)
            return
        }

        translationState.originalText = clipboardText
        translationState.translatedText = nil
        translationState.error = nil
        translationState.isLoading = true

        popoverController.show(near: cursorPos)

        Task { @MainActor in
            await self.translationService.translate(clipboardText, direction: self.translationState.direction)
        }
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fluenty Coach"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
