//
//  AXPasteboardController.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/29.
//

import Cocoa
import Combine
import Vision

class AXPasteboardController {
    private static var checkModificationTask: Task<Void, Never>?

    static func pasteTextAndCheckModification(_ summary: String, _ interactionID: String) async {
        guard !summary.isEmpty else { return }

        let context = getPasteContext()

        await pasteTextToActiveApp(summary)

        guard let context else { return }

        // 启动检查任务
        // 检查用户是否修改了粘贴内容
        checkModificationTask?.cancel()
        checkModificationTask = Task {
            await withTaskCancellationHandler {
                var cancellable: AnyCancellable?
                cancellable = EventBus.shared.eventSubject
                    .sink { event in
                        if case .recordingStarted = event {
                            checkModificationTask?.cancel()
                        }
                    }

                defer { cancellable?.cancel() }

                try? await Task.sleep(nanoseconds: 5_000_000_000)

                guard !Task.isCancelled else { return }

                checkTextModification(context: context, originalText: summary, interactionID: interactionID)
            } onCancel: {}
        }
    }

    private static func getPasteContext() -> (element: AXUIElement, position: Int, length: Int)? {
        guard let element = AXElementAccessor.getFocusedElement(),
              let rangeValue: AXValue = AXElementAccessor.getAttributeValue(
                  element: element,
                  attribute: kAXSelectedTextRangeAttribute,
              )
        else {
            return nil
        }

        var cursorRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &cursorRange) else {
            return nil
        }

        return (element, cursorRange.location, 0)
    }

    private static func checkTextModification(
        context: (element: AXUIElement, position: Int, length: Int),
        originalText: String,
        interactionID: String,
    ) {
        guard let currentElement = AXElementAccessor.getFocusedElement(),
              CFEqual(context.element, currentElement)
        else {
            return
        }

        guard let pastedText = getTextAtRange(
            element: context.element,
            location: context.position,
            length: originalText.count,
        ) else {
            return
        }

        if pastedText != originalText {
            EventBus.shared.publish(.pastedTextModified(original: originalText, modified: pastedText, interactionID: interactionID))
        }
    }

    /// 获取指定范围的文本
    private static func getTextAtRange(element: AXUIElement, location: Int, length: Int) -> String? {
        guard let totalLength: Int = AXElementAccessor.getAttributeValue(
            element: element,
            attribute: kAXNumberOfCharactersAttribute,
        ) else {
            return nil
        }

        // 检查范围是否合法
        if location < 0 || location >= totalLength {
            return nil
        }

        // 调整长度，避免超出边界
        let actualLength = min(length, totalLength - location)
        if actualLength <= 0 {
            return ""
        }

        var targetRange = CFRangeMake(location, actualLength)
        let targetRangeValue = AXValueCreate(.cfRange, &targetRange)!

        return AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXStringForRangeParameterizedAttribute,
            parameter: targetRangeValue,
        )
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
}
