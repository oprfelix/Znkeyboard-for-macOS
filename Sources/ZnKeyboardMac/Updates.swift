import AppKit
import Security
import SwiftUI

/// Updates in place: checks the latest GitHub release (by hand, or once a day), downloads its DMG,
/// accepts the app inside only if it is signed by this app's Developer ID team and notarized, swaps
/// it in for the running copy and reopens. Same signature, so Accessibility, Screen Recording and
/// the keychain item carry over.
@MainActor
enum Updates {
    static let releasesURL = URL(string: "https://github.com/oprfelix/Znkeyboard-for-macOS/releases/latest")!

    struct Release: Equatable {
        let version: String
        let dmg: URL
        let size: Int
    }

    /// A newer release found by the last check; the menu bar menu offers it.
    private(set) static var available: Release?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Checking

    /// "Check for Updates…" from the menu bar or Settings.
    static func check() {
        Task { @MainActor in
            let result = await latestRelease()
            switch result {
            case .some(.some(let release)) where isNewer(release):
                available = release
                if await ask(L.updateAvailable(release.version), L.updateAvailableNote(currentVersion), primary: L.updateNow, secondary: L.later) {
                    install(release)
                }
            case .some:
                available = nil
                _ = await ask(L.upToDate(currentVersion), nil, primary: L.ok, secondary: nil)
            case .none:
                if await ask(L.updateCheckFailed, L.updateCheckFailedNote, primary: L.openReleases, secondary: L.ok) {
                    NSWorkspace.shared.open(releasesURL)
                }
            }
        }
    }

    private static var timer: Timer?

    /// Checks shortly after launch and then every few hours, at most once a day; tells about each
    /// new version once. Off when the user turned automatic checks off.
    static func startAutomaticChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { automaticCheck() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { automaticCheck() }
    }

    private static func automaticCheck() {
        guard Preferences.automaticUpdateChecks,
              Date().timeIntervalSince(Preferences.lastUpdateCheck) > 20 * 3600 else { return }
        Task { @MainActor in
            guard case .some(.some(let release)) = await latestRelease() else { return }
            Preferences.lastUpdateCheck = Date()
            guard isNewer(release) else {
                available = nil
                return
            }
            available = release
            guard Preferences.notifiedUpdate != release.version else { return }
            Preferences.notifiedUpdate = release.version
            if await ask(L.updateAvailable(release.version), L.updateAvailableNote(currentVersion), primary: L.updateNow, secondary: L.later) {
                install(release)
            }
        }
    }

    private static func isNewer(_ release: Release) -> Bool {
        release.version.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    /// nil: GitHub couldn't be reached. .some(nil): reached, but the release has no DMG.
    private static func latestRelease() async -> Release?? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/oprfelix/Znkeyboard-for-macOS/releases/latest")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let link = asset["browser_download_url"] as? String, let url = URL(string: link),
              url.host == "github.com" else { return .some(nil) }
        return .some(Release(version: version, dmg: url, size: asset["size"] as? Int ?? 0))
    }

    // MARK: Installing

    private static var progressWindow: NSWindow?
    private static let progress = UpdateProgress()

    /// Downloads, checks and swaps in [release], then reopens. On any failure the running copy is
    /// left as it was and the download page is offered instead.
    static func install(_ release: Release) {
        guard progressWindow == nil else { return }
        progress.title = L.downloadingUpdate(release.version)
        progress.fraction = 0
        showProgress()
        Task { @MainActor in
            do {
                let dmg = try await download(release)
                progress.title = L.installingUpdate
                progress.fraction = nil
                let newApp = try await Task.detached { try prepare(dmg: dmg, version: release.version) }.value
                try swapIn(newApp)
                relaunch()
            } catch is CancellationError {
                closeProgress()
            } catch {
                closeProgress()
                let reason = (error as? UpdateError)?.message ?? error.localizedDescription
                if await ask(L.updateFailed, L.updateFailedNote(reason), primary: L.openReleases, secondary: L.ok) {
                    NSWorkspace.shared.open(releasesURL)
                }
            }
        }
    }

    struct UpdateError: Error {
        let message: String
    }

    private static var downloadTask: URLSessionDownloadTask?
    private static var progressObservation: NSKeyValueObservation?

    private static func download(_ release: Release) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("znkeyboard-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("ZnKeyboard.dmg")
        let downloaded: URL = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: release.dmg) { location, response, error in
                if let location, (response as? HTTPURLResponse)?.statusCode == 200 {
                    do {
                        try FileManager.default.moveItem(at: location, to: target)
                        continuation.resume(returning: target)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                } else if (error as? URLError)?.code == .cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: UpdateError(message: L.downloadFailed))
                }
            }
            progressObservation = task.progress.observe(\.fractionCompleted) { value, _ in
                let fraction = value.fractionCompleted
                DispatchQueue.main.async { progress.fraction = fraction }
            }
            downloadTask = task
            task.resume()
        }
        progressObservation = nil
        downloadTask = nil
        let size = (try? FileManager.default.attributesOfItem(atPath: downloaded.path)[.size] as? Int) ?? -1
        guard release.size == 0 || size == release.size else { throw UpdateError(message: L.downloadFailed) }
        return downloaded
    }

    /// Opens the DMG, checks the app inside and copies it next to the running one. Blocking.
    nonisolated private static func prepare(dmg: URL, version: String) throws -> URL {
        let mount = dmg.deletingLastPathComponent().appendingPathComponent("mount")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) else {
            throw UpdateError(message: L.updateDamaged)
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let mounted = mount.appendingPathComponent("ZnKeyboard.app")
        try verify(mounted, version: version)

        let current = Bundle.main.bundleURL
        let staged = current.deletingLastPathComponent().appendingPathComponent(".ZnKeyboard-\(version).app")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", [mounted.path, staged.path]) else {
            throw UpdateError(message: L.updateNoPermission)
        }
        // The copy must still be the same signed app.
        try verify(staged, version: version)
        return staged
    }

    /// Signed by this app's own team with the same bundle ID, valid, notarized, and the version promised.
    nonisolated private static func verify(_ app: URL, version: String) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError(message: L.updateDamaged)
        }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"\(Bundle.main.bundleIdentifier ?? "")\""
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw UpdateError(message: L.updateNotTrusted)
        }
        // Gatekeeper's own verdict, which includes notarization.
        guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) else {
            throw UpdateError(message: L.updateNotTrusted)
        }
    }

    /// The Developer ID team that signs ZnKeyboard; an update from anyone else is refused.
    nonisolated private static let teamID = "6DSHU7W7LQ"

    /// Replaces the running bundle with [newApp] in one step; the running copy keeps working until it quits.
    private static func swapIn(_ newApp: URL) throws {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            try? FileManager.default.removeItem(at: newApp)
            throw UpdateError(message: L.updateNoPermission)
        }
    }

    private static func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open '\(path)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: Windows

    private static func showProgress() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: UpdateProgressView(model: progress) {
            downloadTask?.cancel()
        }))
        window.title = "ZnKeyboard"
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        progressWindow = window
        bringToFront()
        window.makeKeyAndOrderFront(nil)
    }

    private static func closeProgress() {
        progressWindow?.close()
        progressWindow = nil
        restorePolicy()
    }

    /// Back to menu-bar-only once no window of ours (Settings, progress) is open.
    private static func restorePolicy() {
        if !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// A menu-bar-only app is often refused activation, leaving its windows behind others; as a
    /// regular app for the moment, it comes to the front (as Settings does).
    private static func bringToFront() {
        if NSApp.activationPolicy() == .accessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// An alert in front of everything; true when the first button was chosen.
    private static func ask(_ title: String, _ message: String?, primary: String, secondary: String?) async -> Bool {
        bringToFront()
        defer { restorePolicy() }
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.addButton(withTitle: primary)
        if let secondary { alert.addButton(withTitle: secondary) }
        return alert.runModal() == .alertFirstButtonReturn
    }
}

final class UpdateProgress: ObservableObject {
    @Published var title = ""
    /// nil while installing, when there is nothing to count.
    @Published var fraction: Double? = 0
}

private struct UpdateProgressView: View {
    @ObservedObject var model: UpdateProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.title).font(.headline)
            if let fraction = model.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                Button(L.cancel, action: cancel).disabled(model.fraction == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
