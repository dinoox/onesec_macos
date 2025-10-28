import SwiftUI

@MainActor
class OverlayController {
    static let shared = OverlayController()

    private var panels: [UUID: NSPanel] = [:]

    private let shadowPadding: CGFloat = 40

    private init() {}

    @discardableResult
    func showOverlay(@ViewBuilder content: () -> some View) -> UUID {
        let statusFrame = StatusPanelManager.shared.getPanelFrame()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: content)

        // 计算 overlay 的位置：StatusPanel 正上方，水平居中
        let spacing: CGFloat = 4 // StatusPanel 和 overlay 之间的间距
        let overlayX = statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2
        let overlayY = statusFrame.origin.y + statusFrame.height + spacing - shadowPadding

        let panel = NSPanel(
            contentRect: NSRect(x: overlayX, y: overlayY, width: contentSize.width, height: contentSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        setupPanel(panel, hosting: hosting)
        panel.alphaValue = 0.0
        panel.animations = ["alphaValue": createSpringFadeInAnimation()]
        panel.animator().alphaValue = 1.0

        let uuid = UUID()
        panels[uuid] = panel

        return uuid
    }

    func updateContent(uuid: UUID, @ViewBuilder content: () -> some View) {
        guard let panel = panels[uuid] else {
            return
        }

        let statusFrame = StatusPanelManager.shared.getPanelFrame()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: content)

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
        panel.becomeKey()
        panel.makeKeyAndOrderFront(nil)
    }

    func hideOverlay(uuid: UUID) {
        guard let panel = panels[uuid] else {
            return
        }

        panel.close()
        panels.removeValue(forKey: uuid)
    }

    func hideAllOverlays() {
        let uuids = Array(panels.keys)
        uuids.forEach { hideOverlay(uuid: $0) }
    }

    // 设置自动关闭（用于需要自动消失的 overlay，如通知）
    func setAutoHide(uuid: UUID, after delay: TimeInterval) {
        guard panels[uuid] != nil else {
            log.warning("panel not exist: \(uuid)")
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            guard !Task.isCancelled else { return }

            hideOverlay(uuid: uuid)
        }
    }
}

extension OverlayController {
    private func createSpringFadeInAnimation() -> CASpringAnimation {
        let springAnimation = CASpringAnimation(keyPath: "alphaValue")
        springAnimation.fromValue = 0.0
        springAnimation.toValue = 1.0
        springAnimation.mass = 1.0
        springAnimation.stiffness = 300.0
        springAnimation.damping = 20.0
        springAnimation.initialVelocity = 0.0
        springAnimation.duration = springAnimation.settlingDuration
        return springAnimation
    }

    /// 创建 hosting view 并计算内容大小
    private func createHostingViewAndGetSize(@ViewBuilder content: () -> some View) -> (
        hosting: NSHostingView<AnyView>, size: NSSize
    ) {
        let hosting = NSHostingView(rootView: AnyView(content().padding(shadowPadding)))

        let tempPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        tempPanel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        return (hosting, hosting.fittingSize)
    }
}
