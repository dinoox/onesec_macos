import ApplicationServices

class AXAtomic {
    static func getCursorRange() -> CFRange? {
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
        return cursorRange
    }

    /// 获取指定范围的文本
    static func getTextAtRange(location: Int, length: Int) -> String? {
        guard
            let element = AXElementAccessor.getFocusedElement(),
            let totalLength: Int = AXElementAccessor.getAttributeValue(
                element: element,
                attribute: kAXNumberOfCharactersAttribute,
            )
        else {
            return nil
        }

        // 检查范围是否合法
        if location < 0 || location >= totalLength {
            return nil
        }

        // 根据边界调整长度
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
}
