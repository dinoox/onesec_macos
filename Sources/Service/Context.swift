//
//  Context.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import ApplicationServices
import Cocoa

class ContextService {
    static func getAppInfo() -> AppInfo {
        guard AXIsProcessTrusted() else {
            return AppInfo(appName: "权限不足", bundleID: "unknown", shortVersion: "unknown")
        }

        var appName = "未知应用"
        var bundleID = "未知 Bundle ID"
        var shortVersion = "未知版本"

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appName = frontApp.localizedName ?? "未知应用"
            bundleID = frontApp.bundleIdentifier ?? "未知 Bundle ID"

            if let bundleURL = frontApp.bundleURL {
                let bundle = Bundle(url: bundleURL)
                if let bundle {
                    if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        shortVersion = version
                    }
                }
            }
        }

        return AppInfo(appName: appName, bundleID: bundleID, shortVersion: shortVersion)
    }
    
    static func pasteTextToActiveApp(_ text: String) {
        guard AXIsProcessTrusted() else {
            log.error("Server result writeback failed - 需要辅助功能权限")
            return
        }
        
        // 保存当前剪贴板内容
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        // log.info("Old pasteboard contents \(oldContents ?? "")")
        
        // 将文本复制到剪贴板
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 模拟 Cmd+V 粘贴
        let source = CGEventSource(stateID: .hidSystemState)
        
        // 按下 Cmd
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        
        // 按下 V
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        
        // 释放 V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        
        // 释放 Cmd
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        // 发送事件
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        
        // 延迟后恢复原剪贴板内容
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let oldContents {
                pasteboard.clearContents()
                pasteboard.setString(oldContents, forType: .string)
            }
        }
    }
    
    static func getFocusContextAndElementInfo(includeContext: Bool = true) -> (FocusContext, FocusElementInfo?) {
        guard AXIsProcessTrusted() else {
            return (FocusContext(inputContent: "权限不足", selectedText: ""), nil)
        }
        
        var inputContent = ""
        var focusElementInfo: FocusElementInfo?
        
        // 获取当前焦点元素
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement
            
            // 获取焦点元素信息
            focusElementInfo = getFocusElementInfo(from: axElement)
            
            // 获取元素的值（文本内容）- 只有在需要上下文时才获取
            if includeContext {
                log.debug("includeContext::: \(includeContext)")
            } else {
                // log.info("⏰ 跳过元素值获取（普通模式）")
            }
        }
         
        if inputContent.isEmpty {
            inputContent = ""
        }
        
        // 获取选中文本 - 只有在需要上下文时才获取（命令模式）
        let selectedText: String = if includeContext {
            getSelectedByAXAPI()
        } else {
            // log.info("⏰ 跳过选中文本获取（普通模式）")
            ""
        }
        
        let focusContext = FocusContext(inputContent: inputContent, selectedText: selectedText)
        log.info("⏰ getFocusContextAndElementInfo 完成")
        return (focusContext, focusElementInfo)
    }
    
    static func getFocusElementInfo(from element: AXUIElement) -> FocusElementInfo {
        let axRole = getAttributeValue(element: element, attribute: kAXRoleAttribute) ?? ""
        let axRoleDescription = getAttributeValue(element: element, attribute: kAXRoleDescriptionAttribute) ?? ""
        let axPlaceholderValue = getAttributeValue(element: element, attribute: kAXPlaceholderValueAttribute) ?? ""
        let axDescription = getAttributeValue(element: element, attribute: kAXDescriptionAttribute) ?? ""
        
        return FocusElementInfo(
            windowTitle: getWindowTitle(for: element),
            axRole: axRole,
            axRoleDescription: axRoleDescription,
            axPlaceholderValue: axPlaceholderValue,
            axDescription: axDescription,
        )
    }
    
    static func getSelectedByAXAPI() -> String {
        guard AXIsProcessTrusted() else {
            log.warning("辅助功能权限不足，无法获取选中文本")
            return ""
        }
        
        let systemWideElement = AXUIElementCreateSystemWide()

        var selectedTextValue: AnyObject?
        let errorCode = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &selectedTextValue)
        
        if errorCode == .success {
            // 直接使用，因为 AXUIElementCopyAttributeValue 返回的就是 AXUIElement
            let selectedTextElement = selectedTextValue as! AXUIElement
            
            var selectedText: AnyObject?
            let textErrorCode = AXUIElementCopyAttributeValue(selectedTextElement, kAXSelectedTextAttribute as CFString, &selectedText)
          
            if textErrorCode == .success, let selectedTextString = selectedText as? String, !selectedTextString.isEmpty {
                log.debug("成功获取选中文本: \(selectedTextString.prefix(50))...")
                return selectedTextString
            } else {
                return ""
            }
        } else {
            log.warning("无法获取焦点元素，错误代码: \(errorCode.rawValue)")
            return ""
        }
    }
    
    static func getWindowTitle(for element: AXUIElement) -> String {
        // 向上遍历找到窗口元素
        var currentElement = element
        
        // 最多向上遍历5层
        for _ in 0 ..< 5 {
            if let role = getAttributeValue(element: currentElement, attribute: kAXRoleAttribute),
               role.contains("Window")
            {
                if let title = getAttributeValue(element: currentElement, attribute: kAXTitleAttribute),
                   !title.isEmpty
                {
                    return title
                }
            }
            
            // 获取父元素
            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent) == .success,
               let parentElement = parent
            {
                currentElement = parentElement as! AXUIElement
            } else {
                break
            }
        }
        
        return "未知窗口"
    }
    
    static func getAttributeValue(element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        
        if result == .success, let unwrappedValue = value {
            return "\(unwrappedValue)"
        }
        
        return nil
    }
}
