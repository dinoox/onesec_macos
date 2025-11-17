import AppKit

/// Provider：使用 NSPasteboardItemDataProvider 来捕获 "对方是否请求粘贴内容"
final class LazyPasteProvider: NSObject, NSPasteboardItemDataProvider {

    var hitCallback: (() -> Void)?

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType)
    {
        hitCallback?()   // 有应用来读内容
    }
}

class AXTest {
    static let shared = AXTest()

    // 探针命中标记
    private static var lazyPasteProbeHit = false

    /// 状态回调
    private static func markHit() {
        lazyPasteProbeHit = true
        log.info("Lazy Paste Probe Hit (modern API)")
    }

    /// 使用现代 NSPasteboardItem + 数据提供者实现的粘贴探针
    static func runLazyPasteboardProbe() {
        let pb = NSPasteboard.general
        lazyPasteProbeHit = false

        // 清空剪贴板（prepareForNewContents 也可）
        pb.clearContents()

        // 创建一个 NSPasteboardItem
        let item = NSPasteboardItem()

        // 创建 data provider
        let provider = LazyPasteProvider()
        provider.hitCallback = { AXTest.markHit() }

        // 注册惰性提供类型
        item.setDataProvider(provider, forTypes: [.string])

        // 写入剪贴板（现代方式）
        pb.writeObjects([item])

        // 调用你的 “模拟粘贴”
        AXPasteboardController.simulatePaste()

        // 等待回调触发（最多 300ms）
        let deadline = Date().addingTimeInterval(0.3)
        while !lazyPasteProbeHit, Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }

        // 输出结果
        if lazyPasteProbeHit {
            print("🧪 LazyPaste Probe：检测到对方请求数据 → 应该在可输入环境")
        } else {
            print("🧪 LazyPaste Probe：没有收到请求 → 应该不在可输入环境")
        }
    }
}