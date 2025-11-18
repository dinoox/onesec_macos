import AppKit

class AXTest {
    private static var lazyPasteProbeHit = false
    private static var readCount = 0
    private static var timeMarker: Date?

    @objc static func pasteboard(_ pasteboard: NSPasteboard, provideDataForType _: NSPasteboard.PasteboardType) {
        lazyPasteProbeHit = true
        readCount += 1

        if let startTime = timeMarker {
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            if readCount == 1 {
                NSPasteboard.general.declareTypes([.string], owner: self)
                log.info("第一次simulatePaste到第一次被读的时间: \(String(format: "%.2f", elapsed))ms")
            } else if readCount == 2 {
                pasteboard.setString("ABC", forType: .string)
                log.info("第二次declareTypes到第二次被读取的时间: \(String(format: "%.2f", elapsed))ms")
            } else {
                log.info("剪切板被读取 \(readCount) 次, 间隔时间: \(String(format: "%.2f", elapsed))ms")
            }
            timeMarker = nil
        }

        log.info("剪切板被读取 \(readCount) 次")
        timeMarker = Date()
    }

    static func runLazyPasteboardProbe() {
        readCount = 0
        timeMarker = nil
        lazyPasteProbeHit = false

        NSPasteboard.general.declareTypes([.string], owner: self)
        timeMarker = Date()
        AXPasteboardController.simulatePaste()

        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(0.6)
            while !lazyPasteProbeHit, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            if lazyPasteProbeHit {
                print("🧪 LazyPaste 探针：检测到目标应用请求粘贴数据，推断当前在可输入环境")
            } else {
                print("🧪 LazyPaste 探针：未检测到粘贴数据请求，推断当前不在可输入环境")
            }
        }
    }
}
