import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyService: HotkeyService!
    private var translationService: TranslationService!
    private var aiTranslationService: AITranslationService!
    private var translationStyleStore: TranslationStyleStore!
    private var accessibilityService: AccessibilityService!
    private var speechService: SpeechService!
    private var popoverController: PopoverController!
    private var translationState: TranslationState!
    private var historyStore: HistoryStore!
    private var permissionState: PermissionState!

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private var permissionTimer: Timer?
    private var onboardingShownThisLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        translationState = TranslationState()
        accessibilityService = AccessibilityService()
        speechService = SpeechService()
        historyStore = HistoryStore()
        permissionState = PermissionState()
        translationStyleStore = TranslationStyleStore()
        aiTranslationService = AITranslationService(style: translationStyleStore)
        translationService = TranslationService(
            state: translationState,
            history: historyStore,
            ai: aiTranslationService
        )
        popoverController = PopoverController(
            state: translationState,
            translation: translationService,
            accessibility: accessibilityService,
            speech: speechService
        )

        hotkeyService = HotkeyService { [weak self] in
            self?.handleDoubleCopy()
        }
        hotkeyService.start()

        startPermissionMonitor()

        // First-run: register the app with the system (one-time prompt) and guide
        // the user through granting access with our own friendly window.
        if !permissionState.isTrusted {
            accessibilityService.requestSystemPromptOnce()
            showOnboardingWindow()
        }
    }

    // MARK: - Permission monitoring

    /// Polls the Accessibility trust state so SwiftUI reflects it live and the
    /// onboarding window can confirm/auto-dismiss the moment access is granted.
    private func startPermissionMonitor() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasTrusted = self.permissionState.isTrusted
                self.permissionState.refresh()
                if !wasTrusted && self.permissionState.isTrusted {
                    // Access just granted — celebrate by closing the nag window.
                    self.onboardingWindow?.performClose(nil)
                }
            }
        }
    }

    // MARK: - Double Copy Handler

    private func handleDoubleCopy() {
        let cursorPos = NSEvent.mouseLocation

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

        // Text surrounding the selection, sent to DeepL as unbilled context so
        // short fragments translate with their surroundings in mind.
        translationState.sourceContext = focusedElement.flatMap {
            accessibilityService.contextSnippet(
                around: clipboardText,
                in: $0,
                selectedRange: translationState.sourceSelectionRange
            )
        }

        // The API key gate only applies to the DeepL engine; the AI engine runs
        // through cursor-agent, which reuses the user's Cursor login instead.
        if TranslationEngine.current == .deepl,
           UserDefaults.standard.string(forKey: "deeplApiKey")?.isEmpty != false {
            popoverController.showApiKeySetup(near: cursorPos)
            return
        }

        // Without accessibility, translation still works but Replace can't paste.
        // Nudge the user once (no repeated system modal) so they can enable it.
        if !permissionState.isTrusted && !onboardingShownThisLaunch {
            showOnboardingWindow()
        }

        translationState.originalText = clipboardText
        translationState.translatedText = nil
        translationState.error = nil
        translationState.isLoading = true

        popoverController.show(near: cursorPos)

        Task { @MainActor in
            await self.translationService.translate(
                clipboardText,
                source: self.translationState.sourceLanguage,
                target: self.translationState.targetLanguage
            )
        }
    }

    // MARK: - Windows

    func openSettingsWindow() {
        permissionState.refresh()
        showWindow(
            &settingsWindow,
            title: "Fluenty Coach — Settings",
            size: NSSize(width: 480, height: 640),
            rootView: SettingsView(
                permission: permissionState,
                accessibility: accessibilityService,
                ai: aiTranslationService,
                style: translationStyleStore
            )
        )
    }

    func openHistoryWindow() {
        showWindow(
            &historyWindow,
            title: "Fluenty Coach — History",
            size: NSSize(width: 420, height: 460),
            rootView: HistoryView(store: historyStore, speech: speechService)
        )
    }

    private func showOnboardingWindow() {
        onboardingShownThisLaunch = true
        permissionState.refresh()
        showWindow(
            &onboardingWindow,
            title: "Welcome to Fluenty Coach",
            size: NSSize(width: 420, height: 420),
            rootView: OnboardingView(
                permission: permissionState,
                accessibility: accessibilityService,
                onDone: { [weak self] in self?.onboardingWindow?.performClose(nil) }
            )
        )
    }

    private func showWindow<V: View>(_ slot: inout NSWindow?, title: String, size: NSSize, rootView: V) {
        if let existing = slot, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        slot = window
    }
}
