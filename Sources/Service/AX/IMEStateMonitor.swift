import ApplicationServices
import Carbon
import Cocoa

class IMEStateMonitor {
    static let shared = IMEStateMonitor()

    private(set) var isComposing = false
    private var composingCount = 0
    private var cachedIMEState: (sourceID: String, isActive: Bool)?

    private enum KeyCode {
        static let space: Int64 = 49
        static let enter: Int64 = 36
        static let escape: Int64 = 53
        static let delete: Int64 = 51
        static let backspace: Int64 = 117
        static let arrows: Set<Int64> = [123, 124, 125, 126]
    }

    private static let imeKeywords: Set<String> = ["inputmethod", "Pinyin", "Japanese", "Korean", "Wubi", "Zhuyin", "IM."]

    private init() {}

    func handleCGEvent(type: CGEventType, event: CGEvent) {
        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard !hasModifierKeys(flags), !KeyCode.arrows.contains(keyCode) else { return }
        guard isInputMethodActive() else { return resetComposing() }

        switch keyCode {
        case KeyCode.space, KeyCode.enter, KeyCode.escape:
            endComposing()
        case KeyCode.delete, KeyCode.backspace:
            handleDelete()
        default:
            handleCharacterInput(event)
        }
    }

    private func hasModifierKeys(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    }

    private func isInputMethodActive() -> Bool {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let sourceIDPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID)
        else { return false }

        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
        if let cached = cachedIMEState, cached.sourceID == sourceID {
            return cached.isActive
        }

        let isActive = Self.imeKeywords.contains { sourceID.contains($0) }
        cachedIMEState = (sourceID, isActive)
        return isActive
    }

    private func handleDelete() {
        guard composingCount > 0 else { return }
        composingCount -= 1
        if composingCount == 0 {
            resetComposing("Composing stack is empty")
        }
    }

    private func handleCharacterInput(_ event: CGEvent) {
        guard let string = getEventString(event),
              !string.trimmingCharacters(in: .controlCharacters).isEmpty
        else { return }

        if string.unicodeScalars.allSatisfy({ $0.isASCII }) {
            isComposing = true
            composingCount += 1
            log.debug("Composing: \(string) depth: \(composingCount)")
        } else {
            resetComposing("Composing done: \(string)")
        }
    }

    private func getEventString(_ event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }

        var chars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    private func endComposing() {
        guard isComposing else { return }
        resetComposing("Composing done")
    }

    private func resetComposing(_ reason: String = "") {
        if !reason.isEmpty {
            log.debug("Reset Composing: \(reason)")
        }
        isComposing = false
        composingCount = 0
    }
}
