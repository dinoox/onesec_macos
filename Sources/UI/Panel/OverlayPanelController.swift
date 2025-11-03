import Combine
import SwiftUI

@MainActor
class OverlayController {
    static let shared = OverlayController()

    private var panels: [UUID: NSPanel] = [:]
    private let shadowPadding: CGFloat = 50
    private var savedMouseLocation: NSRect?
    private var mouseMonitor: Any?

    private init() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.savedMouseLocation = self?.getMouseLocationBounds()
        }
    }

    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @discardableResult
    func showOverlay(@ViewBuilder content: (_ panelId: UUID) -> some View) -> UUID {
        let statusFrame = StatusPanelManager.shared.getPanelFrame()

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        // 计算 overlay 的位置：StatusPanel 正上方，水平居中 (36 为 StatusPanel 的高度)
        let spacing: CGFloat = 4 // StatusPanel 和 overlay 之间的间距
        let overlayX = statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2
        let overlayY = statusFrame.origin.y + 36 + spacing - shadowPadding

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

    @discardableResult
    func showOverlayAboveSelection(@ViewBuilder content: (_ panelId: UUID) -> some View) -> UUID? {
        var selectionBounds = getSelectionBounds()

        // 检查边界有效性（无法获取或返回无效的0值）
        if selectionBounds == nil || selectionBounds!.width < 1 || selectionBounds!.height < 1 {
            // Fallback: 使用保存的鼠标位置
            guard let mouseBounds = savedMouseLocation else {
                return nil
            }
            selectionBounds = mouseBounds
        }

        let bounds = selectionBounds!

        // 获取屏幕信息
        guard let screen = NSScreen.main else {
            log.warning("无法获取屏幕信息")
            return nil
        }
        let screenHeight = screen.frame.height

        // 先创建 UUID
        let uuid = UUID()

        // 使用 UUID 创建内容
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        // AX API返回的是Cocoa坐标系（左上角为原点，Y轴向下）
        // 需要转换为NSWindow坐标系（左下角为原点，Y轴向上）

        let spacing: CGFloat = 8

        // X坐标：左对齐
        let overlayX = bounds.origin.x - shadowPadding

        // Y坐标转换：
        // 1. AX的Y是从屏幕顶部开始的距离
        // 2. 文本顶部(AX) = bounds.origin.y
        // 3. 转换为NSWindow坐标：screenHeight - axY
        // 4. Panel应该在文本上方，所以Y坐标更大
        let textTopInWindowCoords = screenHeight - bounds.origin.y
        let overlayY = textTopInWindowCoords + spacing - shadowPadding

        let panel = NSPanel(
            contentRect: NSRect(x: overlayX, y: overlayY, width: contentSize.width, height: contentSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupPanel(panel, hosting: hosting)
        panel.isMovableByWindowBackground = true
        panel.alphaValue = 0.0
        panel.animations = ["alphaValue": createSpringFadeInAnimation()]
        panel.animator().alphaValue = 1.0

        panels[uuid] = panel
        return uuid
    }

    /// 使用鼠标位置创建fallback边界（Cocoa坐标系）
    private func getMouseLocationBounds() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else {
            return nil
        }

        // 转换为Cocoa坐标系（屏幕顶部为Y=0）
        let screenFrame = screen.frame
        let screenHeight = screenFrame.height
        let axY = screenHeight - (mouseLocation.y - screenFrame.origin.y)

        // 创建一个最小边界（使用鼠标位置）
        return NSRect(
            x: mouseLocation.x - screenFrame.origin.x,
            y: axY - 10, // 10为补偿
            width: 100, // 最小宽度
            height: 20 // 最小高度
        )
    }

    /// 获取选中文本的屏幕坐标
    private func getSelectionBounds() -> NSRect? {
        guard let element = AXElementAccessor.getFocusedElement(),
              let rangeValue: AXValue = AXElementAccessor.getAttributeValue(
                  element: element,
                  attribute: kAXSelectedTextRangeAttribute
              )
        else {
            return nil
        }

        log.info("rangeValue: \(rangeValue)")
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }
        log.info("range: \(range.location), \(range.length)")
        // 获取文本边界（支持光标位置和选中文本）
        guard let boundsValue: AXValue = AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXBoundsForRangeParameterizedAttribute,
            parameter: rangeValue
        ) else {
            return nil
        }

        log.info("boundsValue: \(boundsValue)we")
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect) else {
            return nil
        }

        // 如果没有选中文本，给光标位置一个最小宽度
        if range.length == 0 {
            rect.size.width = max(rect.size.width, 1)
        }

        return NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
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
