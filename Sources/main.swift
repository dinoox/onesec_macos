import Cocoa
import Combine
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var connectionCenter: ConnectionCenter!
    var inputController: InputController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        CommandParser.main()

        SoundService.shared.initialize()
        SignalHandler.shared.setupSignalHandlers()

        connectionCenter = ConnectionCenter.shared

        setupPermissionObserver()

        StatusPanelManager.shared.showPanel()
        Task {
            // try? await Task.sleep(nanoseconds: 1_000_000_000)
            // EventBus.shared.publish(.notificationReceived(.recordingFailed))
        }
    }

    private func setupPermissionObserver() {
        connectionCenter.$permissionsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePermissionChange()
            }
            .store(in: &cancellables)
    }

    private func handlePermissionChange() {
        let hasPermissions = connectionCenter.hasPermissions()
        if hasPermissions, inputController == nil {
            inputController = InputController()
        } else if !hasPermissions, inputController != nil {
            log.warning("Permission Revoked, Cleaning InputController")
            inputController = nil
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
