import Foundation
import ServiceManagement

/// Opening at login, through macOS's own login items. The state lives with macOS, not in
/// Preferences, since the user can change it in System Settings too.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Registered, but off in System Settings → General → Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            CaretLog.note("login item \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// On by default like the Windows app, once, and only from /Applications: a copy run from a
    /// download or disk image may not be there at the next login.
    static func enableOnce() {
        guard !Preferences.loginItemEnabledOnce, Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        Preferences.loginItemEnabledOnce = true
        set(true)
    }
}
