import Foundation

/// The anonymous daily ping behind the numbers on znkeyboard.2amz.com: a random id made on this Mac,
/// the platform, the version and how many times text was translated since the last
/// ping. Never any text, key or setting. Off when the user turns it off in Settings.
@MainActor
enum UsageStats {
    private static let endpoint = URL(string: "https://znkeyboard.2amz.com/api/ping")!
    private static var sending = false

    /// One finished translation or reading translation.
    static func recordUse() {
        guard Preferences.anonymousStats else { return }
        Preferences.pendingUses += 1
    }

    /// Sends the ping once a day; a failed one is tried again later, uses kept.
    static func pingIfDue() {
        guard Preferences.anonymousStats, !sending, Date().timeIntervalSince(Preferences.lastPing) > 20 * 3600 else { return }
        sending = true
        let uses = Preferences.pendingUses
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "id": Preferences.installID, "platform": "macos", "version": Updates.currentVersion, "uses": uses,
        ])
        Task { @MainActor in
            defer { sending = false }
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            Preferences.lastPing = Date()
            Preferences.pendingUses -= uses
        }
    }
}
