import AppKit

/// "Check for Updates…" from the menu bar or Settings: compares this version with the latest
/// GitHub release and offers the download.
@MainActor
enum Updates {
    static let releasesURL = URL(string: "https://github.com/oprfelix/Znkeyboard-for-macOS/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func check() {
        Task { @MainActor in
            let latest = await latestReleaseVersion()
            // A menu-bar-only app is often refused activation, leaving the alert behind other windows;
            // as a regular app for the moment, it comes to the front (as Settings does).
            let wasAccessory = NSApp.activationPolicy() == .accessory
            if wasAccessory { NSApp.setActivationPolicy(.regular) }
            defer { if wasAccessory { NSApp.setActivationPolicy(.accessory) } }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            let current = currentVersion
            if let latest {
                if latest.compare(current, options: .numeric) == .orderedDescending {
                    alert.messageText = L.updateAvailable(latest)
                    alert.informativeText = L.updateAvailableNote(current)
                    alert.addButton(withTitle: L.download)
                    alert.addButton(withTitle: L.later)
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesURL) }
                } else {
                    alert.messageText = L.upToDate(current)
                    alert.addButton(withTitle: L.ok)
                    alert.runModal()
                }
            } else {
                alert.alertStyle = .warning
                alert.messageText = L.updateCheckFailed
                alert.informativeText = L.updateCheckFailedNote
                alert.addButton(withTitle: L.openReleases)
                alert.addButton(withTitle: L.ok)
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(releasesURL) }
            }
        }
    }

    /// "0.2.5" from the latest release's tag, or nil when GitHub can't be reached.
    private static func latestReleaseVersion() async -> String? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/oprfelix/Znkeyboard-for-macOS/releases/latest")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}
