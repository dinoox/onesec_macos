import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var recording = RecordingState()
    @State var notificationPanelId: UUID?

    private var overlay: OverlayController { OverlayController.shared }

    var body: some View {
        // 状态指示器
        VStack {
            StatusIndicator(
                recordState: recording.state,
                volume: recording.volume,
                mode: recording.mode
            )
        }
        .onTapGesture {
            overlay.hideAllOverlays()
            MenuBuilder.shared.showMenu(in: StatusPanelManager.shared.getPanel().contentView!)
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
}

extension StatusView {
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
        case .userDataUpdated:
            if ConnectionCenter.shared.isAuthed,
               notificationPanelId != nil,
               ConnectionCenter.shared.hasPermissions()
            {
                overlay.hideOverlay(uuid: notificationPanelId!)
                notificationPanelId = nil
            }
        case let .notificationReceived(notificationType):
            log.info("Receive notification: \(notificationType)")

            var autoHide = true
            var showTimerTip = false
            var autoCloseDuration = 3
            if notificationType != .recordingTimeoutWarning {
                recording.state = .idle
            } else {
                showTimerTip = true
                autoCloseDuration = 15
            }

            if notificationType == .authTokenFailed {
                autoHide = false
            }

            showNotificationMessage(
                title: notificationType.title, content: notificationType.content,
                autoHide: autoHide,
                showTimerTip: showTimerTip,
                autoCloseDuration: autoCloseDuration,
            )
        case let .hotWordAddRequested(word):
            ContentCard<EmptyView>.show(title: "热词添加", content: "检测到热词 \"\(word)\", 是否添加到词库？", actionButtons: [
                ActionButton(title: "添加") {
                    Task { @MainActor in
                        do {
                            let response = try await HTTPClient.shared.post(
                                path: "/hotword/create",
                                body: ["hotword": word]
                            )

                            if response.success == true {
                                Tooltip.show(content: "添加成功 请在词库中查看")
                            }
                        } catch {}
                    }
                },
            ])
        case let .serverResultReceived(text, _, processMode, polishedText):
            recording.state = .idle
            if text.isEmpty {
                return
            }

            Task {
                let canPaste = await canPasteNow()
                defer {
                    handleAlert(canPaste: canPaste, processMode: processMode, text: text, polishedText: polishedText)
                }

                if processMode == .terminal && text.newlineCount >= 1 {
                    return
                }
                if canPaste {
                    await AXPasteboardController.pasteTextToActiveApp(text)
                    return
                }
            }
        case let .terminalLinuxChoice(_, _, _, commands):
            recording.state = .idle
            log.info("Receive terminalLinuxChoice: \(commands)")
            LinuxCommandCard.show(commands: commands)
        default:
            break
        }
    }

    private func canPasteNow() async -> Bool {
        // 1.
        // 首先根据白名单使用零宽字符复制测试方法
        if isAppShouldTestWithZeroWidthChar() {
            log.info("Use zero width char paste test")
            return await AXPasteboardController.whasTextInputFocus()
        }

        // 2.
        // 当前应用有焦点元素, 说明支持 AX
        // 如果是可编辑的元素则直接粘贴, 否则弹窗
        let element = AXElementAccessor.getFocusedElement()
        let isEditable = element.map { AXElementAccessor.isEditableElement($0) } ?? false

        if element != nil, !isAppWithoutAXSupport() {
            log.info("Use AX paste test")
            return isEditable
        }

        // 3.
        // 对于 AX 黑名单应用
        // 使用粘贴探针检测是否可以粘贴
        log.info("Fallback to paste probe")
        return await AXPasteProbe.isPasteAllowed()
    }

    private func handleAlert(canPaste: Bool, processMode: TextProcessMode, text: String, polishedText: String) {
        let cardWidth: CGFloat = getTextCardWidth(text: text)

        if canPaste {
            if processMode == .translate {
                guard Config.shared.USER_CONFIG.translation.showComparison else { return }
                ContentCard<EmptyView>.show(title: "输入原文", content: polishedText, onTap: nil, actionButtons: nil, cardWidth: cardWidth, spacingX: 8, spacingY: 14, panelType: .translate, canMove: true)
            } else if processMode == .terminal, text.newlineCount >= 1 {
                LinuxCommandCard.show(commands: [LinuxCommand(distro: "", command: text, displayName: "")])
            }
        } else {
            if processMode == .translate {
                guard Config.shared.USER_CONFIG.translation.showComparison else { return }
                MultiContentCard.show(title: "识别结果", items: [
                    ContentItem(title: "原文", content: polishedText),
                    ContentItem(title: "译文", content: text),
                ], cardWidth: cardWidth, panelType: .translate)
                return
            }
            if recording.mode == .command {
                ContentCard<EmptyView>.showAboveSelection(title: "处理结果", content: text, cardWidth: cardWidth, spacingX: 8, spacingY: 14, panelType: .command)
            } else {
                ContentCard<EmptyView>.show(title: "识别结果", content: text, cardWidth: cardWidth, panelType: .notification)
            }
        }
    }

    private func showNotificationMessage(
        title: String, content: String,
        autoHide: Bool = true, onTap: (() -> Void)? = nil,
        showTimerTip: Bool = false, autoCloseDuration: Int = 3,
    ) {
        notificationPanelId = overlay.showOverlay(
            content: { panelId in
                NotificationCard(
                    title: title,
                    content: content,
                    panelId: panelId,
                    autoHide: autoHide,
                    showTimerTip: showTimerTip,
                    autoCloseDuration: autoCloseDuration,
                    onTap: onTap,
                    onClose: {
                        notificationPanelId = nil
                    }
                )
            },
            panelType: .notificationSystem
        )
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
}
