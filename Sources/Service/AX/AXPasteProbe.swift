import AppKit

class AXPasteProbe {
    static func runPasteProbe(_ content: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let provider = PasteboardDataProvider(text: content)
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.string])
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let startTime = CFAbsoluteTimeGetCurrent()
        AXPasteboardController.simulatePaste()

        for _ in 0 ..< 100 {
            if provider.wasRequested {
                let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                log.debug("🧪 可输入 (\(String(format: "%.1f", elapsed))ms)")
                return true
            }
            try? await sleep(10)
        }
        log.debug("🧪 不可输入")
        return false
    }

    static func isPasteAllowed() async -> Bool {
        let pasteboard = NSPasteboard.general
        let oldContent = pasteboard.string(forType: .string)
        let canPaste = await runPasteProbe("")

        if let oldContent,
           let currentContent = pasteboard.string(forType: .string),
           currentContent.isEmpty
        {
            pasteboard.clearContents()
            pasteboard.setString(oldContent, forType: .string)
        }
        return canPaste
    }
}
