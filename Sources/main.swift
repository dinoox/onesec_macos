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
        try? DatabaseService.shared.initialize()
        StatusPanelManager.shared.orderFront()

        Task { @MainActor in
            AXSelectionObserver.shared.startObserving()
            AXTranslationAccessor.setupMouseUpListener()
        }

        SyncScheduler.shared.start()
        PersonaScheduler.shared.checkAndFetchIfNeeded()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
