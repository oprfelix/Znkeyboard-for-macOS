import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ShortcutResult {
    case ok(Shortcut)
    case usedByOther
    case taken
}

/// A key cap that, once clicked, takes the next key combination as the new shortcut.
/// Esc cancels; the reset button returns to the default.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    let apply: (ShortcutAction, Shortcut?) -> ShortcutResult

    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var error: String?
    @State private var monitor: Any?

    init(action: ShortcutAction, apply: @escaping (ShortcutAction, Shortcut?) -> ShortcutResult) {
        self.action = action
        self.apply = apply
        _shortcut = State(initialValue: Preferences.shortcut(for: action))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if shortcut != action.defaultShortcut, !recording {
                    Button(L.resetDefault) { use(nil) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Button(action: recording ? stop : start) {
                    Text(recording ? L.pressShortcut : shortcut.display)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(recording ? Color.accentColor : .primary)
                        .frame(minWidth: 64)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .help(L.shortcutHint)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        error = nil
        recording = true
        HotKeys.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let next = Shortcut(event: event) {
                use(next)
                stop()
            } else {
                error = L.needModifier
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        HotKeys.shared.isPaused = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func use(_ next: Shortcut?) {
        switch apply(action, next) {
        case .ok(let applied):
            shortcut = applied
            error = nil
        case .usedByOther:
            error = L.shortcutUsedByOther
        case .taken:
            error = L.shortcutTaken
        }
    }
}
