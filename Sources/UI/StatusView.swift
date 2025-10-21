import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var recording = RecordingState()
    @State var notification = NotificationState()
    @State var shortcutSettings = ShortcutSettingsState()
    @State var menuBuilder: MenuBuilder?

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
        toggleCard(isVisible: shortcutSettings.isVisible) { visible, opacity in
            shortcutSettings.isVisible = visible
            shortcutSettings.opacity = opacity
        }
    }
    
    // 通用的卡片显示/隐藏切换方法
    private func toggleCard(isVisible: Bool, update: @escaping (Bool, Double) -> Void) {
        if isVisible {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                update(true, 0)
            }
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                update(false, 0)
            }
        } else {
            update(true, 0)
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    update(true, 1)
                }
            }
        }
    }

    // 显示通知的方法
    private func showNotificationMessage(title: String, content: String, autoHide: Bool = true) {
        notification.title = title
        notification.content = content

        Task {
            // 立即显示通知占位（触发窗口 resize，但通知是透明的）
            notification.isVisible = true
            notification.opacity = 0

            // 等待布局和 resize 完成
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            // 淡入通知卡片（此时窗口已经 resize 完成，不会影响布局）
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                notification.opacity = 1
            }

            if autoHide {
                // 等3秒后隐藏
                try? await Task.sleep(nanoseconds: 3_000_000_000)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    notification.opacity = 0
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
                notification.isVisible = false
            }
        }
    }

    var body: some View {
        VStack {
            // 快捷键设置卡片
            if shortcutSettings.isVisible {
                ShortcutSettingsCard(onClose: toggleShortcutSettings)
                    .opacity(shortcutSettings.opacity)
                Spacer().frame(height: 8)
            }
            
            // 通知区域
            if notification.isVisible {
                NotificationCard(
                    title: notification.title,
                    content: notification.content,
                    modeColor: recording.modeColor,
                )
                .opacity(notification.opacity)
                Spacer().frame(height: 8)
            }

            // 状态指示器
            StatusIndicator(
                recordState: recording.state,
                volume: recording.volume,
                mode: recording.mode,
            ).onTapGesture {
                showMenu()
            }
        }.padding([.top, .leading, .trailing], 10)
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
            showNotificationMessage(
                title: notificationType.title, content: notificationType.content)
        case .serverTimedout:
            showNotificationMessage(title: "服务超时", content: "服务器响应超时，请稍后重试")
        default:
            break
        }
    }
}
