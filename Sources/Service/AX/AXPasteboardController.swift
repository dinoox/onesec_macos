//
//  AXPasteboardController.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/29.
//

import Cocoa
import Combine
import Vision

struct PasteContext {
    let element: AXUIElement
    let originalText: String
    var lastModifiedText: String
    let interactionID: String
    let position: Int
}

class AXPasteboardController {
    private static var checkModificationTask: Task<Void, Never>?
    private static var currentCancellable: AnyCancellable?
    private static var context: PasteContext?

    static func pasteTextAndCheckModification(_ summary: String, _ interactionID: String) async {
        guard !summary.isEmpty else { return }

        if let element = AXElementAccessor.getFocusedElement(),
           let cursorRange = AXAtomic.getCursorRange()
        {
            context = PasteContext(element: element, originalText: summary, lastModifiedText: "", interactionID: interactionID, position: cursorRange.location)
        }

        await pasteTextToActiveApp(summary)

        guard context != nil else { return }

        // 启动检查任务
        // 检查用户是否修改了粘贴内容
        checkModificationTask?.cancel()
        currentCancellable?.cancel()

        checkModificationTask = Task {
            currentCancellable = EventBus.shared.events.sink { event in
                if case .recordingStarted = event {
                    checkModificationTask?.cancel()
                    Task {
                        await AXSelectionObserver.shared.stopObserving()
                    }
                }
            }

            await AXSelectionObserver.shared.startObserving()
        }
    }

    static func handleTextModifyNotification() {
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            log.info("isComposing: \(IMEStateMonitor.shared.isComposing)")
            if !IMEStateMonitor.shared.isComposing {
                await checkTextModification()
            }
        }
    }

    private static func checkTextModification() async {
        guard let ctx = context else { return }
        guard let currentElement = AXElementAccessor.getFocusedElement(),
              CFEqual(ctx.element, currentElement)
        else {
            return
        }

        let modifiedText = ContextService.getInputContent(
            contextLength: ctx.originalText.count * 2,
            cursorPos: ctx.position + ctx.originalText.count / 2
        ) ?? ""

        if !modifiedText.contains(ctx.originalText), modifiedText != ctx.lastModifiedText {
            context!.lastModifiedText = modifiedText
            // context = ctx
            log.info("Text Modified: \(ctx.originalText) -> \(modifiedText),  cursorPos: \(ctx.position)")
            let body = ["original": ctx.originalText, "modified": modifiedText, "interaction_id": ctx.interactionID]
            _ = try? await HTTPClient.shared.post(path: "/audio/update-text", body: body)
        }
    }

    static func copyCurrentSelectionAndRestore() async -> String? {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        pasteboard.clearContents()

        // 模拟 Cmd+C 复制
        simulateCopy()

        // 等待复制功能完成
        try? await Task.sleep(nanoseconds: 100_000_000)

        let copiedText = pasteboard.string(forType: .string)

        // 恢复原剪贴板内容
        restorePasteboard(oldContents)

        return copiedText
    }

    // 检测是否有文本输入焦点
    // 对于没有 AX 支持的应用,使用零宽字符复制测试方法
    // 策略: 粘贴零宽字符 → 选中它 → 复制 → 检测 changeCount → 撤销
    static func whasTextInputFocus() async -> Bool {
        let testMarker = "\u{200B}"
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(testMarker, forType: .string)

        let oldChangeCount = pasteboard.changeCount

        simulatePaste()
        simulateShiftLeft()
        simulateCopy()

        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 当为选中文本时,  changeCount 依旧会改变
        // 所以这里判断当前复制的新内容是否为零宽字符
        let isZeroCharNotChange = pasteboard.string(forType: .string) == testMarker
        simulateUndo()

        defer { restorePasteboard(oldContents) }

        return (pasteboard.changeCount > oldChangeCount) && isZeroCharNotChange
    }

    static func pasteTextToActiveApp(_ text: String) async {
        log.info("Paste Text To Active App: \(text)")

        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            restorePasteboard(oldContents)
        }
    }

    static func restorePasteboard(_ oldContents: String?) {
        let pasteboard = NSPasteboard.general
        if let oldContents {
            pasteboard.clearContents()
            pasteboard.setString(oldContents, forType: .string)
        }
    }
}

// MARK: - Keyboard Simulation Extension

extension AXPasteboardController {
    static func simulatePaste() {
        if let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
           let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        {
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
        }
    }

    static func simulateShiftLeft() {
        if let leftDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x7B, keyDown: true),
           let leftUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x7B, keyDown: false)
        {
            leftDown.flags = .maskShift
            leftUp.flags = .maskShift
            leftDown.post(tap: .cghidEventTap)
            leftUp.post(tap: .cghidEventTap)
        }
    }

    static func simulateCopy() {
        if let cDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true),
           let cUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: false)
        {
            cDown.flags = .maskCommand
            cUp.flags = .maskCommand
            cDown.post(tap: .cghidEventTap)
            cUp.post(tap: .cghidEventTap)
        }
    }

    static func simulateUndo() {
        if let zDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x06, keyDown: true),
           let zUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x06, keyDown: false)
        {
            zDown.flags = .maskCommand
            zUp.flags = .maskCommand
            zDown.post(tap: .cghidEventTap)
            zUp.post(tap: .cghidEventTap)
        }
    }

    static func simulateDelete(times: Int = 0) {
        let deleteKey: CGKeyCode = 0x33

        for _ in 0 ..< times {
            if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false)
            {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }
}
