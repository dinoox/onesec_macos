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
}
