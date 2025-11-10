//
//  AXElementAccessor.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/29.
//

import ApplicationServices

class AXElementAccessor {
    private static let editableRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
        kAXComboBoxRole,
        kAXWindowRole,
    ]

    /// 获取 AX 元素属性值
    /// 对 String 类型特殊处理, 过滤空串
    static func getAttributeValue<T>(element: AXUIElement, attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard result == .success, let value else {
            return nil
        }

        if T.self == String.self {
            let stringValue = "\(value)"
            return (stringValue.isEmpty ? nil : stringValue) as? T
        }

        return value as? T
    }

    /// 获取 AX 元素参数化属性值
    /// 用于获取需要附加参数的属性值
    static func getParameterizedAttributeValue<T>(
        element: AXUIElement,
        attribute: String,
        parameter: CFTypeRef
    ) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        )

        guard result == .success, let value else {
            return nil
        }

        return value as? T
    }

    static func getParent(of element: AXUIElement) -> AXUIElement? {
        return getAttributeValue(element: element, attribute: kAXParentAttribute)
    }

    static func getChildren(of element: AXUIElement) -> [AXUIElement]? {
        return getAttributeValue(element: element, attribute: kAXChildrenAttribute)
    }

    /// 获取应用焦点元素
    /// 返回当前正在接收键盘输入的 UI 元素
    /// 例如：正在编辑的文本框、被选中的按钮、激活的窗口控件等
    static func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let element: AXUIElement = getAttributeValue(
            element: systemWideElement,
            attribute: kAXFocusedUIElementAttribute
        ) else {
            log.warning("Cannot get focused element")
            return nil
        }

        return element
    }

    static func isEditableElement(_ element: AXUIElement) -> Bool {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        if let roleString = role as? String,
           editableRoles.contains(roleString)
        {
            return true
        }

        log.info("Find extra focus role: \(String(describing: role))")

        var isEditable: AnyObject?
        AXUIElementCopyAttributeValue(element, "AXIsEditable" as CFString, &isEditable)

        return (isEditable as? Bool) ?? false
    }
}
