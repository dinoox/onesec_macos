import Foundation

CommandParser.main()

SoundService.shared.initialize()
SignalHandler.shared.setupSignalHandlers()

let connectionCenter = ConnectionCenter.shared
let inputController = InputController()

RunLoop.main.run()
