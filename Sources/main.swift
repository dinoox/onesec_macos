import Foundation

CommandParser.main()
SignalHandler.shared.setupSignalHandlers()
PermissionManager.shared.checkAllPermissions { results in
    log.info("权限检查完成: \(results)")
}



log.info(Config.AUTH_TOKEN)
log.info(Config.UDS_CHANNEL)
log.info(Config.SERVER)

RunLoop.main.run()
