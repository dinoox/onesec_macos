import Cocoa
import Combine
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var connectionCenter: ConnectionCenter!

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        CommandParser.main()
        SoundService.shared.initialize()
        SignalHandler.shared.setupSignalHandlers()

        connectionCenter = ConnectionCenter.shared
        connectionCenter.initialize()

        StatusPanelManager.shared.showPanel()
        Task { @MainActor in
            AXSelectionObserver.shared.startObserving()
            AXTranslationAccessor.setupMouseUpListener()
        }
    
        SyncScheduler.shared.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
