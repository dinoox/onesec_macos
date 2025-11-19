import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var recording = RecordingState()
    @State var notificationPanelId: UUID?

    private let overlay = OverlayController.shared

    var body: some View {
        // 状态指示器
        StatusIndicator(
            recordState: recording.state,
            volume: recording.volume,
            mode: recording.mode
        ).onTapGesture {
            overlay.hideAllOverlays()
            MenuBuilder.shared.showMenu(in: NSApp.windows.first?.contentView ?? NSView())
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
            ContentCard<EmptyView>.show(title: "热词添加", content: ["检测到热词 \"\(word)\", 是否添加到词库？"], actionButtons: [
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
        case let .serverResultReceived(summary, _, processMode, polishedText):
            recording.state = .idle
            if summary.isEmpty {
                return
            }

            Task {
                var canPaste = false
                let element = AXElementAccessor.getFocusedElement()
                let isEditable = element.map { AXElementAccessor.isEditableElement($0) } ?? false

                // 1.
                // 当前应用有焦点元素, 说明支持 AX
                // 如果是可编辑的元素则直接粘贴, 否则弹窗
                if element != nil {
                    if isEditable {
                        canPaste = true
                        await AXPasteboardController.pasteTextToActiveApp(summary)
                    }
                }

                // 2.
                // 当前应用不支持 AX
                // 首先根据白名单使用零宽字符复制测试方法
                if !canPaste, isAppShouldTestWithZeroWidthChar() {
                    log.info("No focused editable element, attempting zero width char paste test")
                    if await AXPasteboardController.whasTextInputFocus() {
                        canPaste = true
                        await AXPasteboardController.pasteTextToActiveApp(summary)
                    }
                }

                // 3.
                // 使用粘贴探针检测是否可以粘贴
                if !canPaste {
                    log.info("Zero char paste test failed, using paste probe")
                    canPaste = await AXPasteProbe.runPasteProbe(summary)
                }

                log.info("canPaste: \(canPaste)")

                if processMode == .translate {
                    if canPaste {
                        ContentCard<EmptyView>.showAboveSelection(title: "输入原文", content: [polishedText], onTap: nil, actionButtons: nil, cardWidth: 260, spacingX: 8, spacingY: 14, panelType: .translate)
                    } else {
                        ContentCard<EmptyView>.show(title: "识别结果", content: [polishedText, summary], panelType: .translate)
                    }
                    return
                }

                if !canPaste {
                    if recording.mode == .command {
                        ContentCard<EmptyView>.showAboveSelection(title: "处理结果", content: [summary], cardWidth: 260, spacingX: 8, spacingY: 14, panelType: .command)
                    } else {
                        ContentCard<EmptyView>.show(title: "识别结果", content: [summary], panelType: .notification)
                    }
                }
            }
        case let .terminalLinuxChoice(bundleID, appName, endpointIdentifier, commands):
            recording.state = .idle
            log.info("Receive terminalLinuxChoice: \(commands)")
            LinuxCommandChoiceCard.show(commands: commands, bundleID: bundleID, appName: appName, endpointIdentifier: endpointIdentifier)
        default:
            break
        }
    }

    private func showNotificationMessage(
        title: String, content: String, autoHide: Bool = true, onTap: (() -> Void)? = nil,
    ) {
        notificationPanelId = overlay.showOverlay { panelId in
            NotificationCard(
                title: title,
                content: content,
                panelId: panelId,
                modeColor: recording.modeColor,
                autoHide: autoHide,
                onTap: onTap,
                onClose: {
                    notificationPanelId = nil
                }
            )
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
}
