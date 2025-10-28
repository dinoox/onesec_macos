//
//  InputContextAccessor.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/28.
//

import Cocoa
import Vision

class InputContentManager {
    private static func getContextAroundCursor(element: AXUIElement, contextLength: Int = 200)
        -> String?
    {
        // 获取文本长度
        var lengthRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXNumberOfCharactersAttribute as CFString, &lengthRef
            ) == .success,
            let totalLength = lengthRef as? Int
        else {
            log.warning("Cannot get text length")
            return nil
        }

        // 获取光标位置
        var selectedRange: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &selectedRange
            ) == .success,
            let rangeValue = selectedRange as! AXValue?
        else {
            log.warning("Cannot get cursor position")
            return nil
        }

        var cursorRange = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &cursorRange) else {
            return nil
        }

        let cursorPosition = cursorRange.location
        let halfLength = contextLength / 2

        // 计算要获取的范围，确保不超出边界
        let start = max(0, cursorPosition - halfLength)
        let end = min(totalLength, cursorPosition + halfLength)
        let actualLength = end - start

        log.debug("Total: \(totalLength), Cursor: \(cursorPosition), Range: \(start)~\(end)")

        var targetRange = CFRangeMake(start, actualLength)
        let targetRangeValue = AXValueCreate(.cfRange, &targetRange)!

        // 直接获取指定范围的文本
        var textRef: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, targetRangeValue,
                &textRef
            ) == .success,
            let text = textRef as? String
        else {
            log.warning("Cannot get text for range, fallback to full content")
            // 降级方案：获取全部内容
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
                == .success,
                let fullText = value as? String
            {
                let startIndex =
                    fullText.index(
                        fullText.startIndex, offsetBy: start, limitedBy: fullText.endIndex)
                    ?? fullText.startIndex
                let endIndex =
                    fullText.index(fullText.startIndex, offsetBy: end, limitedBy: fullText.endIndex)
                    ?? fullText.endIndex
                return String(fullText[startIndex..<endIndex])
            }
            return nil
        }

        return text
    }
}

class HistoryContextAccessor {
    static let needHistoryLength = 400

    /// 获取输入框上方的聊天历史内容
    static func getChatHistory(from element: AXUIElement) -> String? {
        var current = element
        var bestContent = ""

        for level in 0..<10 {
            guard let parent = ContextService.getParent(of: current) else { break }
            current = parent

            if let content = searchChatContent(in: current, excludeElement: element),
                content.count > bestContent.count
            {
                bestContent = content

                if content.count >= needHistoryLength {
                    log.debug("Level \(level): reached target, stopping")
                    return bestContent
                }
            }
        }

        return bestContent.isEmpty ? nil : bestContent
    }

    private static func searchChatContent(in element: AXUIElement, excludeElement: AXUIElement)
        -> String?
    {
        let text = collectTextMessages(
            from: element, excludeElement: excludeElement, maxChars: needHistoryLength)
        return text.isEmpty ? nil : text
    }

    /// 递归收集文本消息（限制字数，从后往前收集）
    private static func collectTextMessages(
        from element: AXUIElement,
        excludeElement: AXUIElement,
        maxChars: Int,
        depth: Int = 0,
    ) -> String {
        if CFEqual(element, excludeElement) {
            log.debug("[\(depth)] skipping excluded element (self)")
            return ""
        }

        var children: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
                == .success,
            let childrenArray = children as? [AXUIElement]
        else {
            return ""
        }

        let indent = String(repeating: "  ", count: depth)
        log.debug("[\(depth)] children count: \(childrenArray.count)")

        var texts: [String] = []
        var totalChars = 0

        // 从后往前遍历（最新的消息在后面）
        for (index, child) in childrenArray.reversed().enumerated() {
            // 检查是否是要排除的元素
            if CFEqual(child, excludeElement) {
                log.debug("\(indent)[\(depth).\(index)] ✗ excluded element")
                continue
            }

            if containsElement(child, target: excludeElement) {
                log.debug("\(indent)[\(depth).\(index)] ✗ contains excluded element, skipping")
                continue
            }

            guard
                let role = ContextService.getAttributeValue(
                    element: child, attribute: kAXRoleAttribute,
                )
            else {
                continue
            }

            // 收集文本内容
            if role.contains("TextArea") || role.contains("StaticText") || role.contains("Text") {
                if let text = ContextService.getAttributeValue(
                    element: child, attribute: kAXValueAttribute,
                )
                    ?? ContextService.getAttributeValue(
                        element: child, attribute: kAXDescriptionAttribute,
                    )
                {
                    let cleaned = text.replacingOccurrences(
                        of: "\\s+", with: " ", options: .regularExpression,
                    )
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !cleaned.isEmpty, totalChars < maxChars {
                        texts.append(cleaned)
                        totalChars += cleaned.count
                    }
                }
            }
            // 递归搜索容器 - 移除字符数限制，让它完整遍历树
            else if shouldRecurseIntoRole(role) {
                log.debug("\(indent)[\(depth).\(index)] → recursing into \(role)")
                let childText = collectTextMessages(
                    from: child,
                    excludeElement: excludeElement,
                    maxChars: maxChars - totalChars,
                    depth: depth + 1,
                )
                if !childText.isEmpty {
                    texts.append(childText)
                    totalChars += childText.count
                }
            } else {
                log.debug("\(indent)[\(depth).\(index)] ✗ skipping role: \(role)")
            }

            // 只有在收集了足够的文本后才停止
            if totalChars >= maxChars {
                log.debug("\(indent)[\(depth)] reached maxChars limit: \(totalChars)")
                break
            }
        }

        log.debug("[\(depth)] collected \(texts.count) text fragments, total: \(totalChars) chars")

        // 反转回正确顺序，拼接并截取最后maxChars字
        let result = texts.reversed().joined(separator: " ")
        return result.count <= maxChars ? result : String(result.suffix(maxChars))
    }

    /// 判断是否应该递归进入该角色的元素
    private static func shouldRecurseIntoRole(_ role: String) -> Bool {
        let recursiveRoles = [
            "ScrollArea", "Group", "SplitGroup", "List",
            "Row", "Column", "Container", "WebArea",
            "Section", "Pane", "Content", "View",
        ]

        for recursiveRole in recursiveRoles {
            if role.contains(recursiveRole) {
                return true
            }
        }

        return false
    }

    /// 检查元素是否包含目标元素（递归检查所有子元素）
    private static func containsElement(_ element: AXUIElement, target: AXUIElement) -> Bool {
        if CFEqual(element, target) {
            return true
        }

        var children: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
                == .success,
            let childrenArray = children as? [AXUIElement]
        else {
            return false
        }

        for child in childrenArray {
            if containsElement(child, target: target) {
                return true
            }
        }

        return false
    }
}
