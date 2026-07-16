import Foundation
import ApplicationServices
import Observation

/// Observable mirror of the Accessibility permission so SwiftUI views can react
/// live (e.g. the onboarding window updating to "Granted" the instant the user
/// flips the switch in System Settings).
@Observable
@MainActor
final class PermissionState {
    var isTrusted: Bool = AXIsProcessTrusted()

    func refresh() {
        let current = AXIsProcessTrusted()
        if current != isTrusted { isTrusted = current }
    }
}
