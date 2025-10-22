import SwiftUI

@MainActor
class OverlayController {
    static let shared = OverlayController()

    private var panels: [UUID: NSPanel] = [:]

    private let shadowPadding: CGFloat = 40

    private init() {}

    @discardableResult
    func showOverlay(@ViewBuilder content: () -> some View) -> UUID {
        let hosting = NSHostingView(rootView: AnyView(content().padding(shadowPadding)))

        // 创建一个临时的 panel 来获取内容大小
        let tempPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        tempPanel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let contentSize = hosting.fittingSize

        // 获取 StatusPanel 的位置
        guard let statusFrame = StatusPanelManager.shared.getPanelFrame() else {
            return UUID()
        }

        // 计算 overlay 的位置：StatusPanel 正上方，水平居中
        let spacing: CGFloat = 6 // StatusPanel 和 overlay 之间的间距
        let overlayX = statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2
        let overlayY = statusFrame.origin.y + statusFrame.height + spacing - shadowPadding

        let panel = NSPanel(
            contentRect: NSRect(
                x: overlayX, y: overlayY, width: contentSize.width, height: contentSize.height,
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        setupPanel(panel, hosting: hosting)

        // 添加弹性渐入动画效果
        panel.alphaValue = 0.0

        let springAnimation = CASpringAnimation(keyPath: "alphaValue")
        springAnimation.fromValue = 0.0
        springAnimation.toValue = 1.0
        springAnimation.mass = 1.0
        springAnimation.stiffness = 300.0
        springAnimation.damping = 20.0
        springAnimation.duration = springAnimation.settlingDuration

        panel.animations = ["alphaValue": springAnimation]
        panel.animator().alphaValue = 1.0

        let uuid = UUID()
        panels[uuid] = panel

        return uuid
    }

    func updateContent(uuid: UUID, @ViewBuilder content: () -> some View) {
        guard let panel = panels[uuid] else {
            return
        }

        let hosting = NSHostingView(rootView: AnyView(content().padding(shadowPadding)))

        // 获取新内容的大小
        let tempPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        tempPanel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let contentSize = hosting.fittingSize

        // 获取 StatusPanel 的位置
        guard let statusFrame = StatusPanelManager.shared.getPanelFrame() else {
            return
        }

        // 计算新的位置
        let spacing: CGFloat = 8
        let overlayX = statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2
        let overlayY = statusFrame.origin.y + statusFrame.height + spacing - shadowPadding

        // 更新内容视图
        panel.contentView = hosting

        // 平滑动画更新位置和大小
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NSRect(
                    x: overlayX, y: overlayY, width: contentSize.width, height: contentSize.height,
                ),
                display: true,
            )
        }
    }

    // 检查指定 UUID 的 panel 是否可见
    func isVisible(uuid: UUID) -> Bool {
        guard let panel = panels[uuid] else { return false }
        return panel.isVisible
    }

    private func setupPanel(_ panel: NSPanel, hosting: NSHostingView<some View>) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.contentView = hosting
        panel.makeKeyAndOrderFront(nil)
    }

    // 关闭指定 UUID 的 panel
    func hideOverlay(uuid: UUID) {
        guard let panel = panels[uuid] else {
            return
        }

        panel.close()
        panels.removeValue(forKey: uuid)
    }

    // 关闭所有 panel
    func hideAllOverlays() {
        let uuids = Array(panels.keys)
        uuids.forEach { hideOverlay(uuid: $0) }
    }

    // 设置自动关闭（用于需要自动消失的 overlay，如通知）
    func setAutoHide(uuid: UUID, after delay: TimeInterval) {
        guard panels[uuid] != nil else {
            log.warning("尝试为不存在的 panel 设置自动关闭: \(uuid)")
            return
        }

        // 创建自动关闭任务
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // 检查任务是否被取消
            guard !Task.isCancelled else { return }

            // 关闭 panel（如果还存在）
            hideOverlay(uuid: uuid)
        }
    }
}
