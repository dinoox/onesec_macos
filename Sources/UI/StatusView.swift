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

    // 显示通知的方法
    private func showNotificationMessage(title: String, content: String, autoHide: Bool = true) {
        // 关闭之前的通知
        if let panelId = notificationPanelId {
            overlay.hideOverlay(uuid: panelId)
        }

        let uuid = overlay.showOverlay {
            NotificationCard(
                title: title,
                content: content,
                modeColor: recording.modeColor,
                onClose: !autoHide ? {
                    if let panelId = notificationPanelId {
                            overlay.hideOverlay(uuid: panelId)
                            notificationPanelId = nil
                        }
                    } : nil
            )
        }
        notificationPanelId = uuid

        if autoHide {
            overlay.setAutoHide(uuid: uuid, after: 3.0)
        }
    }

    var body: some View {
        VStack {
            // 状态指示器
            StatusIndicator(
                recordState: recording.state,
                volume: recording.volume,
                mode: recording.mode,
            ).onTapGesture {
                // 点击时隐藏所有 overlay 并显示菜单
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
            log.info("statusView receive modeUpgraded \(from) \(to)")
            if to == .command {
                recording.mode = to
            }
        case .notificationReceived(let notificationType):
            log.info("notificationReceived: \(notificationType)")
            recording.state = .idle
            showNotificationMessage(
                title: notificationType.title, content: notificationType.content,
            )
        default:
            break
        }
    }
}
