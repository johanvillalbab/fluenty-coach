import AppKit

/// Detects double copy through pasteboard changes instead of a global key event tap.
/// This avoids depending on macOS Input Monitoring permissions for the shortcut flow.
@MainActor
final class HotkeyService {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastCopyTimestamp: TimeInterval = 0
    private var lastClipboardText: String = ""
    private let doubleCopyThreshold: TimeInterval = 0.75
    private let onDoubleCopy: @MainActor () -> Void

    init(onDoubleCopy: @escaping @MainActor () -> Void) {
        self.onDoubleCopy = onDoubleCopy
    }

    func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        let changeDelta = currentChangeCount - lastChangeCount
        lastChangeCount = currentChangeCount

        let text = pasteboard.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - lastCopyTimestamp
        let isDoubleCopy = changeDelta >= 2 || (elapsed <= doubleCopyThreshold && text == lastClipboardText)

        if isDoubleCopy {
            lastCopyTimestamp = 0
            lastClipboardText = ""
            onDoubleCopy()
        } else {
            lastCopyTimestamp = now
            lastClipboardText = text
        }
    }
}
