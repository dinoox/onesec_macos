//
//  AXInputHistoryContextAccessor.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/29.
//

import Cocoa
import Vision

class AXInputHistoryContextAccessor {
    static let needHistoryLength = 300

    private static let textRoles: Set<String> = ["TextArea", "StaticText", "Text", "AXHeading"]
    private static let recursiveRoles: Set<String> = [
        "ScrollArea", "Group", "SplitGroup", "List",
        "Row", "Column", "Container", "WebArea",
        "Section", "Pane", "Content", "View",
    ]

    static func getChatHistory(from element: AXUIElement) -> String? {
        let excludeHash = CFHash(element)
        var current = element
        var bestContent: String?

        for _ in 0 ..< 8 {
            guard let parent = AXElementAccessor.getParent(of: current) else { break }
            current = parent

            if let content = searchChatContent(in: current, excludeHash: excludeHash) {
                if content.count >= needHistoryLength {
                    return content
                }
                if bestContent == nil || content.count > (bestContent?.count ?? 0) {
                    bestContent = content
                }
            }
        }

        return bestContent
    }

    private static func searchChatContent(in element: AXUIElement, excludeHash: CFHashCode) -> String? {
        guard let children = AXElementAccessor.getChildren(of: element), !children.isEmpty else {
            return nil
        }

        var texts: [String] = []
        var charCount = 0
        let maxChars = needHistoryLength

        var i = children.count - 1
        while i >= 0, charCount < maxChars {
            let child = children[i]
            defer { i -= 1 }

            if CFHash(child) == excludeHash {
                continue
            }

            guard let role: String = AXElementAccessor.getAttributeValue(
                element: child, attribute: kAXRoleAttribute
            ) else {
                continue
            }

            let isTextRole = textRoles.contains { role.contains($0) }

            if isTextRole {
                if let text: String = AXElementAccessor.getAttributeValue(
                    element: child, attribute: kAXValueAttribute
                )
                    ?? AXElementAccessor.getAttributeValue(
                        element: child, attribute: kAXDescriptionAttribute
                    )
                    ?? AXElementAccessor.getAttributeValue(
                        element: child, attribute: kAXTitleAttribute
                    )
                {
                    let cleaned = text.cleaned
                    let len = cleaned.count

                    if len > 0, charCount + len <= maxChars {
                        texts.append(cleaned)
                        charCount += len
                    }
                }
            } else {
                let shouldRecurse = recursiveRoles.contains { role.contains($0) }
                if shouldRecurse, charCount < maxChars {
                    if let childText = searchChatContent(in: child, excludeHash: excludeHash) {
                        let len = childText.count
                        if len > 0 {
                            texts.append(childText)
                            charCount += len
                        }
                    }
                }
            }
        }

        guard !texts.isEmpty else { return nil }

        // 反转并拼接
        let result = texts.reversed().joined(separator: " ")

        // 截断到 maxChars
        return result.count > maxChars
            ? String(result.suffix(maxChars))
            : result
    }
}
