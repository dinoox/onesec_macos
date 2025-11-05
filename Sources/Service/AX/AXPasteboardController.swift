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
        let source = CGEventSource(stateID: .hidSystemState)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cUp?.flags = .maskCommand

        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)

        // 等待复制功能完成
        try? await Task.sleep(nanoseconds: 100_000_000)

        let copiedText = pasteboard.string(forType: .string)

        // 恢复原剪贴板内容
        pasteboard.clearContents()
        if let oldContents {
            pasteboard.setString(oldContents, forType: .string)
        }

        return copiedText
    }

    static func pasteTextToActiveApp(_ text: String) async {
        log.info("Paste Text To Active App: \(text)")

        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 模拟 Cmd+V 粘贴
        let source = CGEventSource(stateID: .hidSystemState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand

        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if pasteboard.string(forType: .string) == text, let oldContents {
                pasteboard.clearContents()
                pasteboard.setString(oldContents, forType: .string)
            }
        }
    }
}
