import Foundation

SignalHandler.shared.setupSignalHandlers()
PermissionManager.shared.checkAllPermissions { results in
    log.info("权限检查完成: \(results)")
}

RunLoop.main.run()
