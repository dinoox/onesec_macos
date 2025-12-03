//
//  Context.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import ApplicationServices
import Cocoa
import Vision

class ContextService {
    static func getAppInfo() -> AppInfo {
        let frontApp = NSWorkspace.shared.frontmostApplication

        return AppInfo(
            appName: frontApp?.localizedName ?? "Unknown App",
            bundleID: frontApp?.bundleIdentifier ?? "Unknown Bundle ID",
            shortVersion: frontApp?.bundleURL
                .flatMap { Bundle(url: $0) }
                .flatMap {
                    $0.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String
                }
                ?? "Unknown Version",
        )
    }

    static func getHostInfo() -> HostInfo {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN))
        gethostname(&buffer, buffer.count)

        return HostInfo(
            hostname: String(cString: buffer),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        )
    }

    static func getInputContent(contextLength: Int = 200, cursorPos: Int? = nil) -> String? {
        AXInputContentAccessor.getFocusElementInputContent(contextLength: contextLength, cursorPos: cursorPos)
    }

    static func getHistoryContent() -> String? {
        guard let element = AXElementAccessor.getFocusedElement() else {
            return nil
        }

        return AXInputHistoryContextAccessor.getChatHistory(from: element)
    }

    static func getSelectedText() async -> String? {
        guard let element = AXElementAccessor.getFocusedElement() else {
            return await AXPasteboardController.copyCurrentSelectionAndRestore()
        }

        // 方法1: 直接获取选中文本
        if let text: String? = AXElementAccessor.getAttributeValue(
            element: element,
            attribute: kAXSelectedTextAttribute,
        ) {
            return text
        }

        // 方法2: 通过选中范围获取
        if let range: CFTypeRef = AXElementAccessor.getAttributeValue(
            element: element,
            attribute: kAXSelectedTextRangeAttribute
        ) {
            if let text: String? =
                AXElementAccessor.getParameterizedAttributeValue(
                    element: element,
                    attribute: kAXStringForRangeParameterizedAttribute,
                    parameter: range
                )
            {
                return text
            }
        }

        // 使用 Cmd+C 做备用方案
        return await AXPasteboardController.copyCurrentSelectionAndRestore()
    }

    static func getFocusElementInfo() -> FocusElementInfo {
        guard let element = AXElementAccessor.getFocusedElement() else {
            return FocusElementInfo.empty
        }

        let axRole =
            AXElementAccessor.getAttributeValue(
                element: element,
                attribute: kAXRoleAttribute
            ) ?? ""
        let axRoleDescription: String =
            AXElementAccessor.getAttributeValue(
                element: element,
                attribute: kAXRoleDescriptionAttribute
            ) ?? ""
        let axPlaceholderValue: String =
            AXElementAccessor.getAttributeValue(
                element: element,
                attribute: kAXPlaceholderValueAttribute
            ) ?? ""
        let axDescription: String =
            AXElementAccessor.getAttributeValue(
                element: element,
                attribute: kAXDescriptionAttribute
            ) ?? ""

        return FocusElementInfo(
            windowTitle: getWindowTitle(for: element),
            axRole: axRole,
            axRoleDescription: axRoleDescription,
            axPlaceholderValue: axPlaceholderValue,
            axDescription: axDescription,
        )
    }

    static func getWindowTitle(for element: AXUIElement) -> String {
        var currentElement = element

        for _ in 0 ..< 10 {
            if let role: String = AXElementAccessor.getAttributeValue(
                element: currentElement,
                attribute: kAXRoleAttribute
            ),
                role.contains("Window")
            {
                if let title: String = AXElementAccessor.getAttributeValue(
                    element: currentElement,
                    attribute: kAXTitleAttribute
                ),
                    !title.isEmpty
                {
                    return title
                }
            }

            currentElement =
                AXElementAccessor.getParent(of: currentElement)
                    ?? currentElement
        }

        return "Unknown Window"
    }
}
