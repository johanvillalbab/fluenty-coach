import AppKit
import SwiftUI

@MainActor
final class PopoverController {
    private var panel: NSPanel?
    private var hostingView: NSView?   // strong ref so ARC doesn't drop it
    private let state: TranslationState
    private let translation: TranslationService
    private let accessibility: AccessibilityService
    private let speech: SpeechService

    private let panelWidth: CGFloat = 320
    private var panelHeight: CGFloat = 240

    init(state: TranslationState, translation: TranslationService, accessibility: AccessibilityService, speech: SpeechService) {
        self.state = state
        self.translation = translation
        self.accessibility = accessibility
        self.speech = speech

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func show(near rawPoint: NSPoint) {
        if panel == nil { buildPanel() }
        position(panel, near: rawPoint)
        panel?.orderFrontRegardless()
    }

    func showApiKeySetup(near rawPoint: NSPoint) {
        destroyPanel()
        buildApiKeyPanel()
        position(panel, near: rawPoint)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func buildPanel() {
        let rootView = TranslationPopoverView(
            state: state,
            translation: translation,
            accessibility: accessibility,
            speech: speech,
            onDismiss: { [weak self] in self?.hide() }
        )
        buildPanelWith(rootView: AnyView(rootView))
    }

    private func buildApiKeyPanel() {
        let rootView = ApiKeySetupView(
            onSave: { [weak self] _ in
                // Defer so we're not modifying the view hierarchy from within a view callback
                Task { @MainActor [weak self] in
                    self?.destroyPanel()
                    self?.buildPanel()
                }
            },
            onDismiss: { [weak self] in self?.hide() }
        )
        buildPanelWith(rootView: AnyView(rootView))
    }

    private func buildPanelWith(rootView: AnyView) {
        // Size the panel to the content (TimerStack pattern). With no AppKit shadow
        // and Liquid Glass providing the rounded edge, a content-sized panel leaves
        // no hard-cornered ghost rectangle around the glass.
        let hv = NSHostingView(rootView: rootView)
        hv.layoutSubtreeIfNeeded()
        let fitting = hv.fittingSize
        let height = fitting.height > 1 ? fitting.height : panelHeight
        let size = NSSize(width: panelWidth, height: height)
        panelHeight = height
        hv.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.contentView = hv
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false                  // glass supplies depth; AppKit shadow bled a square frame
        p.animationBehavior = .none          // prevents Tahoe transform-animation crash
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false

        hostingView = hv
        panel = p
    }

    private func destroyPanel() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    @objc private func appDidResignActive() {
        hide()
    }

    private func position(_ panel: NSPanel?, near rawPoint: NSPoint) {
        guard let panel else { return }
        let offset: CGFloat = 14
        var x = rawPoint.x + offset
        var y = rawPoint.y - panelHeight - offset

        if let screen = NSScreen.screenContaining(point: rawPoint) {
            let frame = screen.visibleFrame
            x = min(x, frame.maxX - panelWidth - 4)
            x = max(x, frame.minX + 4)
            y = max(y, frame.minY + 4)
            y = min(y, frame.maxY - panelHeight - 4)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
