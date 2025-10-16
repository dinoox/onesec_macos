import Foundation

CommandParser.main()

SoundService.shared.initialize()
SignalHandler.shared.setupSignalHandlers()
PermissionManager.shared.checkAllPermissions { results in
    log.info("Check permission: \(results)")
}


log.info(ConnectionCenter.shared)
let voiceInputController = VoiceInputController()

RunLoop.main.run()
