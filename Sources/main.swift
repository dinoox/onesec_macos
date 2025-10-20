import Foundation

CommandParser.main()

SoundService.shared.initialize()
SignalHandler.shared.setupSignalHandlers()

_ = ConnectionCenter.shared
_ = InputController()

RunLoop.main.run()
