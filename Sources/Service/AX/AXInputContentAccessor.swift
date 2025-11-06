//
//  AXInputContentAccessor.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/28.
//

import Cocoa
import Vision

class AXInputContentAccessor {
    static func getFocusElementInputContent(contextLength: Int = 200, cursorPos: Int? = nil) -> String? {
        guard let element = AXElementAccessor.getFocusedElement() else {
            return nil
        }

        guard let totalLength: Int = AXElementAccessor.getAttributeValue(
            element: element, attribute: kAXNumberOfCharactersAttribute
        ), totalLength > 0 else {
            return nil
        }

        if contextLength <= 0 {
            return getFullContent(element: element)
        }

        var cursorPos = cursorPos
        if cursorPos == nil {
            guard let rangeValue: AXValue = AXElementAccessor.getAttributeValue(
                element: element, attribute: kAXSelectedTextRangeAttribute
            ) else {
                return nil
            }

            var cursorRange = CFRange()
            guard AXValueGetValue(rangeValue, .cfRange, &cursorRange) else {
                return nil
            }
            cursorPos = cursorRange.location
        }
        let half = contextLength >> 1
        let start = max(0, cursorPos! - half)
        let length = min(totalLength - start, contextLength)

        var targetRange = CFRangeMake(start, length)
        guard let rangeValuePtr = AXValueCreate(.cfRange, &targetRange) else {
            return nil
        }

        if let text: String = AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXStringForRangeParameterizedAttribute,
            parameter: rangeValuePtr
        ) {
            return text.cleaned
        }

        return getFullContent(element: element)
    }

    private static func getFullContent(element: AXUIElement) -> String? {
        guard let fullText: String = AXElementAccessor.getAttributeValue(
            element: element, attribute: kAXValueAttribute
        ), !fullText.isEmpty else {
            return nil
        }
        return fullText.cleaned
    }
}
