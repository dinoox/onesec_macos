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
    let interactionID: String
    let position: Int
    let originalText: String
    var lastModifiedText: String
}

class AXPasteboardController {
    private static var checkModificationTask: Task<Void, Never>?
    private static var currentCancellable: AnyCancellable?
    private static var context: PasteContext?

    private static var lazyPasteProbeHit = false

    static func pasteTextAndCheckModification(_ summary: String, _ interactionID: String) async {
        guard !summary.isEmpty else { return }

        if let element = AXElementAccessor.getFocusedElement(),
           let cursorRange = AXAtomic.getCursorRange(),
           cursorRange.location == 0 // 当前只处理无前文的情况
        {
            context = PasteContext(element: element, interactionID: interactionID, position: cursorRange.location, originalText: summary, lastModifiedText: "")
        }

        await pasteTextToActiveApp(summary)

        guard context != nil else { return }

        // 启动检查任务
        // 检查用户是否修改了粘贴内容
        // 延迟发送至下一轮录音周期开始
        // checkModificationTask?.cancel()
        // currentCancellable?.cancel()

        // checkModificationTask = Task {
        //     currentCancellable = EventBus.shared.events.sink { event in
        //         if case .recordingStarted = event {
        //             Task {
        //                 checkModificationTask?.cancel()
        //                 await AXSelectionObserver.shared.stopObserving()
        //                 await submitTextModification()
        //             }
        //         }
        //     }

        //     await AXSelectionObserver.shared.startObserving()
        // }
    }

    private static func submitTextModification() async {
        guard context != nil else { return }
        defer { context = nil }

        let body = ["original": context!.originalText, "modified": context!.lastModifiedText, "interaction_id": context!.interactionID]
        do {
            let response = try await HTTPClient.shared.post(path: "/audio/update-text", body: body)
            if response.success == true,
               let extractedTerm = response.dataDict!["extracted_term"] as? String
            {
                EventBus.shared.publish(.hotWordAddRequested(word: extractedTerm))
            }
        } catch {
            log.error("Update text failed: \(error)")
        }
    }

    static func checkTextModification() {
        guard let ctx = context else { return }
        guard let currentElement = AXElementAccessor.getFocusedElement(),
              CFEqual(ctx.element, currentElement)
        else {
            return
        }

        var modifiedText = AXAtomic.getTextAtRange(location: ctx.position, length: ctx.originalText.count) ?? ""
        if modifiedText.isEmpty {
            return
        }

        if ctx.originalText.last != modifiedText.last {
            let extendedLength = ctx.originalText.count * 2
            if let extendedText = AXAtomic.getTextAtRange(location: ctx.position, length: extendedLength),
               !extendedText.isEmpty
            {
                modifiedText = extendedText
            }
        }

        if modifiedText != ctx.originalText, modifiedText != ctx.lastModifiedText,
           !ConnectionCenter.shared.currentRecordingAppContext.focusContext.inputContent.starts(with: modifiedText)
        {
            context!.lastModifiedText = modifiedText
            log.info("Text Modified: \(ctx.originalText) -> \(modifiedText)")
        }
    }

    @MainActor
    static func copyCurrentSelectionAndRestore() async -> String? {
        let pasteboard = NSPasteboard.general

        // 保存原始剪贴板状态
        let oldContents: String? = pasteboard.string(forType: .string)
        let oldChangeCount = pasteboard.changeCount

        // 模拟 Cmd+C 复制
        pasteboard.clearContents()
        simulateCopy()

        // 等待复制功能完成
        try? await sleep(150)
        let copiedText = pasteboard.string(forType: .string)

        // 恢复原剪贴板内容
        restorePasteboard(oldContents, oldChangeCount)
        return copiedText
    }

    // 检测是否有文本输入焦点
    // 对于没有 AX 支持的应用,使用零宽字符复制测试方法
    // 策略: 粘贴零宽字符 → 选中它 → 复制 → 检测 changeCount → 撤销
    static func whasTextInputFocus() async -> Bool {
        let testMarker = "\u{200B}"
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // if await copyCurrentSelectionAndRestore() != nil {
        //     return true
        // }

        pasteboard.clearContents()
        pasteboard.setString(testMarker, forType: .string)

        let oldChangeCount = pasteboard.changeCount

        simulatePaste()
        simulateShiftLeft()
        simulateCopy()

        try? await sleep(100)

        // 当为选中文本时,  changeCount 依旧会改变
        // 所以这里判断当前复制的新内容是否为零宽字符
        let isZeroCharNotChange = pasteboard.string(forType: .string) == testMarker
        // simulateUndo()

        defer { restorePasteboard(oldContents) }

        return (pasteboard.changeCount > oldChangeCount) && isZeroCharNotChange
    }

    static func pasteTextToActiveApp(_ text: String) async {
        log.info("Paste Text To Active App: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "") \(text)")

        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()
        try? await sleep(300)

        restorePasteboard(oldContents)
    }

    static func restorePasteboard(_ oldContents: String?, _ oldChangeCount: Int = 0) {
        let pasteboard = NSPasteboard.general
        if let oldContents,
           pasteboard.changeCount - oldChangeCount <= 2 || oldChangeCount == 0
        {
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

class PasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    let text: String
    var wasRequested = false

    init(text: String) {
        self.text = text
    }

    func pasteboard(_: NSPasteboard?, item _: NSPasteboardItem, provideDataForType _: NSPasteboard.PasteboardType) {
        wasRequested = true
        // item.setString(text, forType: type)
    }
}
