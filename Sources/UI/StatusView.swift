import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var recording = RecordingState()
    @State var menuBuilder: MenuBuilder?
    @State var settingsPanelId: UUID?
    @State var notificationPanelId: UUID?

    private let overlay = OverlayController.shared

    // 显示菜单
    private func showMenu() {
        if menuBuilder == nil {
            menuBuilder = MenuBuilder(onShortcutSettings: toggleShortcutSettings)
        }

        if let button = NSApp.windows.first?.contentView {
            menuBuilder?.showMenu(in: button)
        }
    }

    // 切换快捷键设置卡片显示/隐藏
    private func toggleShortcutSettings() {
        if let panelId = settingsPanelId, overlay.isVisible(uuid: panelId) {
            overlay.hideOverlay(uuid: panelId)
            settingsPanelId = nil
        } else {
            let uuid = overlay.showOverlay {
                ShortcutSettingsCard(onClose: {
                    if let panelId = settingsPanelId {
                        overlay.hideOverlay(uuid: panelId)
                        settingsPanelId = nil
                    }
                })
            }
            settingsPanelId = uuid
        }
    }

    private func showNotificationMessage(
        title: String, content: String, autoHide: Bool = true, onTap: (() -> Void)? = nil,
    ) {
        if let panelId = notificationPanelId {
            overlay.hideOverlay(uuid: panelId)
        }

        let uuid = overlay.showOverlay {
            NotificationCard(
                title: title,
                content: content,
                modeColor: recording.modeColor,
                onClose: !autoHide
                    ? {
                        if let panelId = notificationPanelId {
                            overlay.hideOverlay(uuid: panelId)
                            notificationPanelId = nil
                        }
                    } : nil,
                onTap: onTap,
            )
        }
        notificationPanelId = uuid

        if autoHide {
            overlay.setAutoHide(uuid: uuid, after: 3.0)
        }
    }

    private func handlePermissionChange(_ permissionsState: [PermissionType: PermissionStatus]) {
        guard !permissionsState.isEmpty else { return }

        if !ConnectionCenter.shared.hasPermissions() {
            if notificationPanelId == nil {
                showPermissionAlert()
                SoundService.shared.playSound(.notification)
            }
        } else if let panelId = notificationPanelId {
            overlay.hideOverlay(uuid: panelId)
            notificationPanelId = nil
        }
    }

    private func showPermissionAlert() {
        let permissionState = ConnectionCenter.shared.permissionsState
        var missingPermissions: [String] = []

        if permissionState[.microphone] != .granted {
            missingPermissions.append("麦克风")
        }
        if permissionState[.accessibility] != .granted {
            missingPermissions.append("辅助功能")
        }

        guard !missingPermissions.isEmpty else { return }

        showNotificationMessage(
            title: "权限缺失",
            content: "需要\(missingPermissions.joined(separator: "、"))权限，点击前往设置",
            autoHide: false,
            onTap: {
                if permissionState[.accessibility] != .granted {
                    PermissionService.shared.request(.accessibility) { _ in }
                } else if permissionState[.microphone] != .granted {
                    PermissionService.shared.request(.microphone) { _ in }
                }
            },
        )
    }

    var body: some View {
        VStack {
            // 状态指示器
            StatusIndicator(
                recordState: recording.state,
                volume: recording.volume,
                mode: recording.mode,
            ).onTapGesture {
                overlay.hideAllOverlays()
                showMenu()
            }
        }.padding([.top, .leading, .trailing], 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(
                EventBus.shared.events
                    .receive(on: DispatchQueue.main),
            ) { event in
                handleEvent(event)
            }
            .onReceive(
                ConnectionCenter.shared.$permissionsState
                    .receive(on: DispatchQueue.main),
            ) { permissionsState in
                handlePermissionChange(permissionsState)
            }
    }

    private func handleEvent(_ event: AppEvent) {
        switch event {
        case .volumeChanged(let volume):
            recording.volume = min(1.0, max(0.0, CGFloat(volume)))
        case .recordingStarted(_, _, _, let recordMode):
            recording.mode = recordMode
            recording.state = .recording
        case .recordingStopped:
            recording.state = .processing
            recording.volume = 0
        case .serverResultReceived:
            recording.state = .idle
        case .modeUpgraded(let from, let to, _):
            log.info("Receive modeUpgraded: \(from) \(to)")
            if to == .command {
                recording.mode = to
            }
        case .notificationReceived(let notificationType):
            log.info("Receive notification: \(notificationType)")
            recording.state = .idle

            var autoHide = true
            if notificationType == .authTokenFailed {
                autoHide = false
            }

            showNotificationMessage(
                title: notificationType.title, content: notificationType.content,
                autoHide: autoHide,
            )
        default:
            break
        }
    }
}
