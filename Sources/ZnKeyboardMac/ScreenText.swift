import AppKit
import Vision

/// Screenshot translation's first half: the user drags over part of the screen with macOS's own
/// screenshot UI, and the text in it is recognised on this Mac. The image never leaves the Mac;
/// only the recognised text is sent for translation.
enum ScreenText {
    /// Needed to capture anything but the desktop picture; asked for once, kept across updates.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (first time) and adds ZnKeyboard to the Screen Recording list.
    static func requestPermission() { CGRequestScreenCaptureAccess() }

    static func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Lets the user drag out a region (Esc cancels) and returns it, or nil when cancelled.
    static func captureRegion() async -> CGImage? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("znkeyboard-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let finished: Bool = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i: interactive selection, -x: no shutter sound, -o: no window shadow.
            process.arguments = ["-i", "-x", "-o", file.path]
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
        guard finished, let image = NSImage(contentsOf: file) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// The text in [image], top to bottom, one recognised line per line.
    static func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    // Vision's origin is bottom-left: higher lines first, then left to right.
                    .sorted { a, b in
                        abs(a.boundingBox.midY - b.boundingBox.midY) > min(a.boundingBox.height, b.boundingBox.height) / 2
                            ? a.boundingBox.midY > b.boundingBox.midY
                            : a.boundingBox.minX < b.boundingBox.minX
                    }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR", "fr-FR", "de-DE", "es-ES", "pt-BR", "it-IT", "ru-RU", "vi-VT", "th-TH", "ar-SA"]
            if let supported = try? request.supportedRecognitionLanguages() {
                request.recognitionLanguages = preferred.filter(supported.contains)
            }
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Mostly Chinese characters: screenshot translation into Chinese then goes to English instead.
    static func isMostlyChinese(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let han = letters.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        return Double(han.count) / Double(letters.count) > 0.5
    }
}
