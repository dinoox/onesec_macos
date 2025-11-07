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
    
    /// 获取当前行字符数
    static func getCurrentLineCharCount() -> Int? {
        guard let range = getCurrentLineRange() else {
            log.info("getCurrentLineRange11: nil")
            return nil }
        log.info("getCurrentLineRange11: \(range.location), \(range.length)")
        return range.length
    }
    
    /// 获取当前行以及上下两行的内容
    static func getCurrentLineWithContext() -> String? {
        guard let element = AXElementAccessor.getFocusedElement(),
              let cursorRange = getCursorRange() else { return nil }
        
        let cursorPos = cursorRange.location
        let lineNumber: Int? = AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXLineForIndexParameterizedAttribute,
            parameter: cursorPos as CFTypeRef
        )
        
        guard let lineNum = lineNumber else { return nil }
        
        var lines: [String] = []
        for offset in -1...1 {
            let targetLine = lineNum + offset
            if targetLine < 0 { continue }
            
            guard let lineRange: CFRange = AXElementAccessor.getParameterizedAttributeValue(
                element: element,
                attribute: kAXRangeForLineParameterizedAttribute,
                parameter: targetLine as CFTypeRef
            ) else { 
                log.info("wocao: nil")
                continue }
            
            var range = lineRange
            let rangeValue = AXValueCreate(.cfRange, &range)!
            if let text: String = AXElementAccessor.getParameterizedAttributeValue(
                element: element,
                attribute: kAXStringForRangeParameterizedAttribute,
                parameter: rangeValue
            ) {
                lines.append(text)
            }
        }
        
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    
    private static func getCurrentLineRange() -> CFRange? {
        guard let element = AXElementAccessor.getFocusedElement(),
              let cursorRange = getCursorRange() else { return nil }
        
        let cursorPos = cursorRange.location
        log.info("getCurrentLineRange: \(cursorPos)")
        let lineNumber: Int? = AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXLineForIndexParameterizedAttribute,
            parameter: cursorPos as CFTypeRef
        )
        
        log.info("getCurrentLineRange: \(lineNumber)")
        guard let lineNum = lineNumber else { return nil }
        
        return AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXRangeForLineParameterizedAttribute,
            parameter: lineNum as CFTypeRef
        )
    }
}
