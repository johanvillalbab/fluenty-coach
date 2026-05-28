import AppKit

extension NSScreen {
    static func screenContaining(point: NSPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }
}
