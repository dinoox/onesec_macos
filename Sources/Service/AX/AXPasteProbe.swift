import AppKit

class AXPasteProbe {
    private static var lazyPasteProbeHit = false
    private static var readCount = 0
    private static var timeMarker: Date?
    private static var pasteContent: String = ""

    static func runPasteProbe(_ content: String) async -> Bool {
        readCount = 0
        timeMarker = nil
        lazyPasteProbeHit = false
        pasteContent = content

        NSPasteboard.general.declareTypes([.string], owner: self)
        timeMarker = Date()
        AXPasteboardController.simulatePaste()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let deadline = Date().addingTimeInterval(1)
                while !lazyPasteProbeHit, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                log.debug("🧪  \(lazyPasteProbeHit ? "可输入" : "不可输入")")
                continuation.resume(returning: lazyPasteProbeHit)
            }
        }
    }

    static func isPasteAllowed() async -> Bool {
        return await runPasteProbe("")
    }
}

extension AXPasteProbe {
    @objc static func pasteboard(_ pasteboard: NSPasteboard, provideDataForType _: NSPasteboard.PasteboardType) {
        readCount += 1

        if let startTime = timeMarker {
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            if readCount == 1 {
                NSPasteboard.general.declareTypes([.string], owner: self)
                log.info("粘贴被读取时间: \(String(format: "%.2f", elapsed))ms")
            } else if readCount == 2 {
                lazyPasteProbeHit = true
                pasteboard.setString(pasteContent, forType: .string)
                log.info("粘贴后 declareTypes 被读取的时间: \(String(format: "%.2f", elapsed))ms")
            }
        }

        timeMarker = Date()
    }
}
