import Foundation

CommandParser.main()

SignalHandler.shared.setupSignalHandlers()
PermissionManager.shared.checkAllPermissions { results in
    log.info("Check permission: \(results)")
}

ConnectionCenter.shared

RunLoop.main.run()
