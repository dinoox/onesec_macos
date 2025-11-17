import Cocoa

final class LazyPasteProbe {
    static let shared = LazyPasteProbe()
    private init() {}

    private(set) var probeHit = false
    private let probeType = NSPasteboard.PasteboardType("com.example.lazyprobe")
    private var lock = NSLock()

    @objc func pasteboard(_ pasteboard: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        lock.lock(); defer { lock.unlock() }
        if type == probeType || type == .string {
            probeHit = true
            NSLog("[LazyProbe] provideDataForType called for type: \(type)")
        }
    }

    /// 尝试探测：返回 true 表示“很可能”目标应用请求了粘贴（即可输入）
    func runProbe(simulatePaste: Bool = true, timeout: TimeInterval = 0.35) -> Bool {
        lock.lock()
        probeHit = false
        lock.unlock()

        // 记录前台应用 PID（用于后续比对，降低第三方误触发）
        let frontBefore = NSWorkspace.shared.frontmostApplication
        let pidBefore = frontBefore?.processIdentifier ?? -1
        NSLog("[LazyProbe] frontBefore: \(frontBefore?.bundleIdentifier ?? "nil") pid:\(pidBefore)")

        // 准备 pasteboard：只声明自定义 type + 也可以同时声明 .string
        let pb = NSPasteboard.general
        pb.declareTypes([probeType, .string], owner: self)

        // Optionally put a sentinel in the pasteboard for apps that will request actual string
        // (we don't call setString, we rely on provideDataForType to be invoked)
        
        // 发送模拟粘贴（系统级按键）——注意：可能需要权限或会被阻止
        if simulatePaste {
            sendCmdV()
        }

        // 等待回调（runloop 轮询）
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if lock.try() {
                let hit = probeHit
                lock.unlock()
                if hit { break }
            } else {
                // if lock busy, small sleep
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        // 读取结果
        lock.lock()
        let hit = probeHit
        lock.unlock()

        // 检查前后 frontmostApplication：如果触发时 frontmost 与之前相同，判定更可信
        let frontAfter = NSWorkspace.shared.frontmostApplication
        let pidAfter = frontAfter?.processIdentifier ?? -1
        NSLog("[LazyProbe] frontAfter: \(frontAfter?.bundleIdentifier ?? "nil") pid:\(pidAfter)")

        // 判断逻辑：
        // - 如果 probeHit && pidBefore == pidAfter -> 很可能目标应用请求粘贴（可信）
        // - 如果 probeHit && pidBefore != pidAfter -> 可能被第三方触发（不可信）
        // - 如果 !probeHit -> 未检测到请求（可能应用不使用 lazy promise）
        if hit && pidBefore == pidAfter {
            NSLog("[LazyProbe] DETECTED (probeHit && same frontmost PID) -> probably editable")
            return true
        } else if hit {
            NSLog("[LazyProbe] PROBE HIT but frontmost changed -> suspect other app triggered it")
            return false
        } else {
            NSLog("[LazyProbe] NO probe hit within timeout")
            return false
        }
    }

    private func sendCmdV() {
        // 注意：在 macOS 上通过 CGEventPost 发送键盘事件可能需要 “输入监控” 权限，
        // 并且安全机制或其他软件可能拦截或阻止。务必在日志中记录失败情况。
        let src = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) // 'v' key (USB usage)
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        cmdDown?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}