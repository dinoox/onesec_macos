import ApplicationServices
import Cocoa

class AXAtomic {
    static func getCursorPosition() -> NSPoint? {
        guard let element = AXElementAccessor.getFocusedElement(),
              let rangeValue: AXValue = AXElementAccessor.getAttributeValue(
                  element: element,
                  attribute: kAXSelectedTextRangeAttribute
              )
        else {
            return nil
        }

        guard let boundsValue: AXValue = AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXBoundsForRangeParameterizedAttribute,
            parameter: rangeValue
        ) else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect) else {
            return nil
        }

        return NSPoint(x: rect.origin.x, y: rect.origin.y)
    }

    static func getCursorPositionInCocoa() -> NSPoint? {
        log.info("getCursorPositionInCocoa")
        guard let position = getCursorPosition() else {
            return nil
        }

        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(position, $0.frame, false) }) else {
            return nil
        }

        log.info("screen: \(screen.frame), position: \(position)")
        return convertAXPointToCocoa(axPoint: position, screenHeight: screen.frame.height)
    }

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

extension AXAtomic {
    /// 将 AX 坐标系的点转换为 Cocoa 坐标系
    /// AX 坐标系: 原点在左上角, y 轴向下为正
    /// Cocoa 坐标系: 原点在左下角, y 轴向上为正
    static func convertAXPointToCocoa(axPoint: NSPoint, screenHeight: CGFloat) -> NSPoint {
        NSPoint(x: axPoint.x, y: screenHeight - axPoint.y)
    }
}
