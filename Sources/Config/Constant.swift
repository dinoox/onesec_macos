import Foundation

let terminalAppsWithoutAXSupport: Set<String> = [
    "com.termius-dmg.mac",
    "org.tabby",
    "com.vandyke.SecureCRT",
]

let appShouldTestWithZeroWidthChar: Set<String> = [
    "com.tencent.xinWeChat",
]

func isTerminalAppWithoutAXSupport() -> Bool {
    let appInfo = ConnectionCenter.shared.currentRecordingAppContext.appInfo
    return terminalAppsWithoutAXSupport.contains(appInfo.bundleID)
}



func isAppShouldTestWithZeroWidthChar() -> Bool {
    let appInfo = ConnectionCenter.shared.currentRecordingAppContext.appInfo
    return appShouldTestWithZeroWidthChar.contains(appInfo.bundleID)
}
