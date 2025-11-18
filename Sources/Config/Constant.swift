import Foundation

let terminalAppsWithoutAXSupport: Set<String> = [
    "com.termius-dmg.mac",
    "org.tabby",
    "com.vandyke.SecureCRT",
]

let appShouldTestWithZeroWidthChar: Set<String> = [
    "com.tencent.xinWeChat"
]

func isTerminalAppWithoutAXSupport(_ appInfo: AppInfo) -> Bool {
    terminalAppsWithoutAXSupport.contains(appInfo.bundleID)
}

func isAppShouldTestWithZeroWidthChar(_ appInfo: AppInfo) -> Bool {
    appShouldTestWithZeroWidthChar.contains(appInfo.bundleID)
}