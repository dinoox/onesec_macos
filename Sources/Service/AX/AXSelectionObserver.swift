import ApplicationServices
import Cocoa
import SwiftUI

@MainActor
class AXSelectionObserver {
    static let shared = AXSelectionObserver()

    private var observer: AXObserver?
    private var appObserver: NSObjectProtocol?

    private init() {
        setupAppSwitchObserver()
    }

    private func setupAppSwitchObserver() {
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                log.info("Application switched to: \(app.localizedName ?? "Unknown")")
                Task { @MainActor in
                    self.startObserving()
                }
            }
        }
    }

    func startObserving() {
        stopObserving()
        guard let app = NSWorkspace.shared.frontmostApplication,
              let pid = app.processIdentifier as pid_t?,
              app.localizedName != "终端"
        else {
            return
        }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, _, notification, _ in
            Task { @MainActor in
                // log.info("Notification: \(notification)")
                if notification as String == kAXSelectedTextChangedNotification as String {
                    // AXPasteboardController.checkTextModification()
                } else if notification as String == kAXFocusedUIElementChangedNotification as String {
                    log.info("Focused UI Element Changed")
                }
            }
        }, &observer)

        guard result == .success, let observer = observer else {
            return
        }

        self.observer = observer
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

        // 系统更新焦点元素需要时间
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            self.tryActivateAppAccessibility(app: app, attribute: "AXManualAccessibility", retryCount: 5)
            self.tryActivateAppAccessibility(app: app, attribute: "AXEnhancedUserInterface", retryCount: 5)
            self.tryAddNotificationsForFocusedElement(app: app, retryCount: 5)
        }
    }

    private func addAllNotifications(to element: AXUIElement) {
        guard let observer = observer else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let notifications: [String] = [
            kAXSelectedTextChangedNotification as String,
            kAXFocusedUIElementChangedNotification as String,
            kAXValueChangedNotification as String,
        ]

        for notification in notifications {
            AXObserverAddNotification(observer, element, notification as CFString, selfPtr)
        }
    }

    func stopObserving() {
        if let observer = observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
    }
}

extension AXSelectionObserver {
    private func tryAddNotificationsForFocusedElement(app: NSRunningApplication, retryCount: Int = 0) {
        guard observer != nil else { return }

        if let focusedElement = AXElementAccessor.getFocusedElement() {
            log.info("Start Observing: \(app.localizedName ?? "Unknown")")
            addAllNotifications(to: focusedElement)
        } else if retryCount > 0 {
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                self.tryAddNotificationsForFocusedElement(app: app, retryCount: retryCount - 1)
            }
        }
    }

    private func tryActivateAppAccessibility(app: NSRunningApplication, attribute: String, retryCount: Int = 0) {
        if AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(app.processIdentifier),
            attribute as CFString,
            kCFBooleanTrue
        ) == .success {
            log.info("\(attribute) success for app \(app.localizedName ?? "Unknown")")
        } else if retryCount > 0 {
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                tryActivateAppAccessibility(app: app, attribute: attribute, retryCount: retryCount - 1)
            }
        }
    }
}
