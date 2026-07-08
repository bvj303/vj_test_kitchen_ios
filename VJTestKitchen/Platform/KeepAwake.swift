import Foundation
#if os(iOS)
import UIKit
#endif

/// Keeps the display awake during an at-the-stove cooking session, restoring
/// normal sleep behavior when dismissed. Wraps the platform difference:
/// `UIApplication.isIdleTimerDisabled` on iOS vs a `ProcessInfo` activity
/// assertion on macOS (which returns a token that must be held and later
/// ended). Callers hold one instance and flip `isEnabled`.
@MainActor
final class KeepAwake {
    private var isOn = false

    #if os(macOS)
    private var token: (any NSObjectProtocol)?
    #endif

    func enable() {
        guard !isOn else { return }
        isOn = true
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        #elseif os(macOS)
        token = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled,
            reason: "Cooking mode"
        )
        #endif
    }

    func disable() {
        guard isOn else { return }
        isOn = false
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #elseif os(macOS)
        if let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
        #endif
    }
}
