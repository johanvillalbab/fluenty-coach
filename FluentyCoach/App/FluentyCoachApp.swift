import SwiftUI
import AppKit

@main
struct FluentyCoachApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // MenuBarExtra is the correct scene type for menu-bar-only apps on macOS 13+.
        // Using Settings { EmptyView() } with LSUIElement=true creates hidden window
        // infrastructure that triggers _NSWindowTransformAnimation crashes on macOS Tahoe.
        MenuBarExtra {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
    }

    private static let menuBarIcon: NSImage = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let img = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "translate", accessibilityDescription: "Fluenty Coach")
                ?? NSImage()
        }
        img.isTemplate = true   // auto-tints to match menu bar (light/dark mode)
        img.size = NSSize(width: 18, height: 18)
        return img
    }()
}

private struct MenuBarContent: View {
    let appDelegate: AppDelegate

    var body: some View {
        Button("Settings…") {
            appDelegate.openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Fluenty Coach") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
