import Foundation

let accessibilityStatus = PermissionManager.shared.checkStatus(.accessibility)
log.info("辅助功能权限状态: \(accessibilityStatus)")

if accessibilityStatus != .granted {
    PermissionManager.shared.request(.accessibility) { granted in
        log.info("辅助功能权限申请结果: \(granted)")
    }
}

// 检查并请求麦克风权限
let microphoneStatus = PermissionManager.shared.checkStatus(.microphone)
log.info("麦克风权限状态: \(microphoneStatus)")

if microphoneStatus != .granted {
    PermissionManager.shared.request(.microphone) { granted in
        log.info("麦克风权限申请结果: \(granted)")
    }
}

log.info("进入主运行循环...")

RunLoop.main.run()
