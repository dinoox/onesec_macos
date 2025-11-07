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
            let uuid = overlay.showOverlay { _ in
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

        let uuid = overlay.showOverlay { _ in
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
            // 如果没有通知面板，显示权限警告
            if notificationPanelId == nil {
                showPermissionAlert()
                SoundService.shared.playSound(.notification)
            } else {
                // 如果已有通知面板，更新内容
                if let panelId = notificationPanelId {
                    overlay.hideOverlay(uuid: panelId)
                }
                showPermissionAlert()
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
                mode: recording.mode
            ).onTapGesture {
                overlay.hideAllOverlays()
                showMenu()
            }
        }
        .padding(.bottom, 4)
        .frame(width: 200, height: 80, alignment: .bottom)
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
        case let .volumeChanged(volume):
            recording.volume = min(1.0, max(0.0, CGFloat(volume)))
        case let .recordingStarted(mode):
            recording.mode = mode
            recording.state = .recording
        case .recordingStopped:
            recording.state = .processing
            recording.volume = 0
        case let .modeUpgraded(from, to):
            log.info("Receive modeUpgraded: \(from) \(to)")
            if to == .command {
                recording.mode = to
            }
        case .userConfigUpdated:
            if ConnectionCenter.shared.isAuthed,
               notificationPanelId != nil,
               ConnectionCenter.shared.hasPermissions()
            {
                overlay.hideOverlay(uuid: notificationPanelId!)
                notificationPanelId = nil
            }
        case let .notificationReceived(notificationType):
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
        case let .hotWordAddRequested(word):
            overlay.showOverlay { panelId in
                let content = "检测到热词 \"\(word)\", 是否添加到词库？"
                ContentCard(
                    panelId: panelId,
                    title: "热词添加",
                    content: content,
                    actionButtons: [
                        ActionButton(title: "添加") {
                            log.info("添加热词: \(word)")
                            Task {
                                do {
                                    let response = try await HTTPClient.shared.post(
                                        path: "/hotword/create",
                                        body: ["hotword": word]
                                    )
                                    log.info("热词创建成功: \(response.message)")
                                } catch {
                                    log.error("热词创建失败: \(error)")
                                }
                            }
                            OverlayController.shared.hideOverlay(uuid: panelId)
                        },
                    ]
                )
            }
        case let .serverResultReceived(summary, interactionID, _, _):
            recording.state = .idle
            // overlay.showOverlay(content: { panelId in
            //     ConvertHandleView(panelId: panelId, filePath: "/Users/wangxiaoyu/Downloads/response.webp")
            // }, extraHeight: 200)
            // return;
            if summary.isEmpty {
                return
            }

            Task { @MainActor in
                let element = AXElementAccessor.getFocusedElement()
                let isEditable = element.map { AXElementAccessor.isEditableElement($0) } ?? false

                // 尝试粘贴文本
                if !isEditable {
                    log.info("No focused editable element, attempting fallback paste")
                    if element == nil, await AXPasteboardController.whasTextInputFocus() {
                        await AXPasteboardController.pasteTextToActiveApp(summary)
                        return
                    }

                    // 显示覆盖层
                    showOverlay(for: recording.mode, with: summary)
                    return
                }

                log.info("Focused editable element found, pasting text")
                await AXPasteboardController.pasteTextAndCheckModification(summary, interactionID)
            }
        default:
            break
        }
    }

    private func showOverlay(for mode: RecordMode, with content: String) {
        let (title, showAboveSelection) = mode == .command
            ? ("翻译结果", true)
            : ("识别结果", false)

        let overlayBuilder: (UUID) -> ContentCard = { panelId in
            ContentCard(
                panelId: panelId,
                title: title,
                content: content
            )
        }

        if showAboveSelection {
            overlay.showOverlayAboveSelection(content: overlayBuilder)
        } else {
            overlay.showOverlay(content: overlayBuilder)
        }
    }
}
