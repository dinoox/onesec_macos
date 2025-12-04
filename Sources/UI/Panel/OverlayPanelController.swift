import Combine
import ObjectiveC
import SwiftUI

@MainActor
class OverlayController {
    static let shared = OverlayController()

    private var panels: [UUID: NSPanel] = [:]
    private let shadowPadding: CGFloat = 30
    private let statusBarHeight: CGFloat = 36
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupScreenChangeListener()
    }

    @discardableResult
    func showOverlay(@ViewBuilder content: (_ panelId: UUID) -> some View, spacingX _: CGFloat = 0, spacingY _: CGFloat = 0, extraHeight: CGFloat = 0, panelType: PanelType? = nil) -> UUID {
        let statusFrame = StatusPanelManager.shared.getPanel().frame

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        var origin = calculateOverlayOrigin(
            statusFrame: statusFrame,
            contentSize: contentSize,
            spacing: 4
        )

        if let panelType = panelType,
           let existingUUID = findPanelByType(panelType),
           let existingPanel = panels[existingUUID],
           existingPanel.panelType == .translate(.above)
        {
            origin = existingPanel.frame.origin

            moveAndUpdateExistingPanel(
                uuid: existingUUID,
                content: content,
                origin: origin,
                contentSize: contentSize,
                extraHeight: extraHeight
            )

            return existingUUID
        }

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight, panelType: panelType)
        panel.panelType = panelType

        setupPanel(panel, hosting: hosting)
        animateFadeIn(panel)

        panels[uuid] = panel
        return uuid
    }

    @discardableResult
    func showOverlayAboveSelection(@ViewBuilder content: (_ panelId: UUID) -> some View, spacingX: CGFloat = 14, spacingY: CGFloat = 14, extraHeight: CGFloat = 0, panelType: PanelType? = nil, expandDirection: ExpandDirection? = nil) -> UUID? {
        let (bounds, isExactBounds) = getValidSelectionBounds()
        guard let bounds = bounds else {
            return nil
        }

        guard let screen = MouseContextService.shared.getMouseScreen() ?? NSScreen.main else {
            return nil
        }

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        let origin = calculateSelectionOverlayOrigin(
            bounds: bounds,
            screenFrame: screen.frame,
            screenHeight: screen.frame.height,
            spacingX: isExactBounds ? 0 : spacingX,
            spacingY: isExactBounds ? 0 : spacingY,
            contentSize: contentSize
        )

        hosting.onSizeChanged = { [weak self] in
            self?.handlePanelSizeChange(uuid: uuid)
        }

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight, panelType: panelType)
        panel.panelType = panelType
        setupPanel(panel, hosting: hosting)

        animateFadeIn(panel)

        panel.expandDirection = expandDirection
        panel.initialOrigin = origin
        panels[uuid] = panel
        return uuid
    }

    @discardableResult
    func showOverlayAbovePoint(point: NSPoint, @ViewBuilder content: (_ panelId: UUID) -> some View, extraHeight: CGFloat = 0, panelType: PanelType? = nil, expandDirection: ExpandDirection? = nil) -> UUID? {
        if let panelType = panelType {
            hideOverlays(panelType)
        }

        guard let screen = MouseContextService.shared.getMouseScreen() ?? NSScreen.main else {
            return nil
        }

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        let origin = calculatePointOverlayOrigin(
            point: point,
            contentSize: contentSize,
            screenFrame: screen.frame,
            spacing: 0
        )

        hosting.onSizeChanged = { [weak self] in
            self?.handlePanelSizeChange(uuid: uuid)
        }

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight, panelType: panelType)
        panel.panelType = panelType

        setupPanel(panel, hosting: hosting)
        animateFadeIn(panel)

        panel.isMovableByWindowBackground = true
        panel.expandDirection = expandDirection
        panel.initialOrigin = origin
        panels[uuid] = panel
        return uuid
    }

    @discardableResult
    func showOverlayOnCenter(@ViewBuilder content: (_ panelId: UUID) -> some View, extraHeight: CGFloat = 0, panelType: PanelType? = nil) -> UUID? {
        guard let screen = NSScreen.main else {
            return nil
        }

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        let origin = calculateCenterOverlayOrigin(
            contentSize: contentSize,
            screenFrame: screen.frame
        )

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight, panelType: panelType)
        panel.panelType = panelType

        setupPanel(panel, hosting: hosting)
        animateFadeIn(panel)

        panels[uuid] = panel
        return uuid
    }

    func updateContent(uuid: UUID, @ViewBuilder content: () -> some View) {
        guard let panel = panels[uuid] else { return }

        let statusFrame = StatusPanelManager.shared.getPanel().frame
        let (hosting, contentSize) = createHostingViewAndGetSize(content: content)

        let origin = calculateOverlayOrigin(
            statusFrame: statusFrame,
            contentSize: contentSize,
            spacing: 8
        )

        panel.contentView = hosting
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NSRect(origin: origin, size: contentSize),
                display: true
            )
        }
    }

    func isVisible(uuid: UUID) -> Bool {
        panels[uuid]?.isVisible ?? false
    }

    func hideOverlay(uuid: UUID) {
        guard let panel = panels[uuid] else { return }
        panel.removeMoveObserver()
        panel.close()
        panels.removeValue(forKey: uuid)
    }

    func hideAllOverlays() {
        panels.keys.forEach { hideOverlay(uuid: $0) }
    }

    func hideOverlays(_ panelType: PanelType) {
        let uuidsToHide = panels.compactMap { uuid, panel in
            panel.panelType == panelType ? uuid : nil
        }
        uuidsToHide.forEach { hideOverlay(uuid: $0) }
    }

    func hideOverlaysExcept(_ panelTypes: [PanelType]) {
        let uuidsToHide = panels.compactMap { uuid, panel in
            panelTypes.contains(where: { $0 == panel.panelType }) ? nil : uuid
        }
        uuidsToHide.forEach { hideOverlay(uuid: $0) }
    }

    private func findPanelByType(_ panelType: PanelType) -> UUID? {
        return panels.first { $0.value.panelType == panelType }?.key
    }

    func setAutoHide(uuid: UUID, after delay: TimeInterval) {
        guard panels[uuid] != nil else {
            log.warning("panel not exist: \(uuid)")
            return
        }

        Task { @MainActor in
            try? await sleep(UInt64(delay * 1000))
            guard !Task.isCancelled else { return }
            hideOverlay(uuid: uuid)
        }
    }

    func getPanel(uuid: UUID) -> NSPanel? {
        panels[uuid]
    }
}

// MARK: - Private Helpers

private extension OverlayController {
    func createPanel(origin: NSPoint, size: NSSize, extraHeight: CGFloat = 0, panelType: PanelType? = nil) -> NSPanel {
        let rect = NSRect(origin: origin, size: NSSize(width: size.width, height: size.height + extraHeight))

        if panelType != .translate(.collapse) {
            hideOverlaysExcept([.notificationSystem])
        }
        if panelType == .editable {
            return EditablePanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        } else {
            return NSPanel(
                contentRect: rect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
        }
    }

    func setupPanel(_ panel: NSPanel, hosting: NSHostingView<some View>) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.contentView = hosting

        if let panelType = panel.panelType, panelType.canMove {
            panel.isMovableByWindowBackground = true
        }

        panel.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let panel = panel, !panel.isUpdatingPosition else {
                return
            }
            panel.wasDragged = true
        }

        if panel.panelType == .editable,
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 11
        {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    func animateFadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0.0
        panel.animations = ["alphaValue": CASpringAnimation.createSpringFadeInAnimation(keyPath: "alphaValue")]
        panel.animator().alphaValue = 1.0
        panel.animations["alphaValue"] = nil
    }

    func clampToScreen(origin: NSPoint, contentSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let actualWidth = contentSize.width - shadowPadding * 2
        let actualHeight = contentSize.height - shadowPadding * 2

        var x = origin.x
        var y = origin.y

        // 检查右边界
        if x + shadowPadding + actualWidth > screenFrame.maxX {
            x = screenFrame.maxX - actualWidth - shadowPadding
        }
        // 检查左边界
        if x + shadowPadding < screenFrame.minX {
            x = screenFrame.minX - shadowPadding
        }
        // 检查上边界
        if y + shadowPadding + actualHeight > screenFrame.maxY {
            y = screenFrame.maxY - actualHeight - shadowPadding
        }
        // 检查下边界
        if y + shadowPadding < screenFrame.minY {
            y = screenFrame.minY - shadowPadding
        }

        return NSPoint(x: x, y: y)
    }

    func calculateOverlayOrigin(statusFrame: NSRect, contentSize: NSSize, spacing: CGFloat, screenFrame: NSRect? = nil) -> NSPoint {
        let origin = NSPoint(
            x: statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2,
            y: statusFrame.origin.y + statusBarHeight + spacing - shadowPadding
        )
        guard let screenFrame = screenFrame ?? ConnectionCenter.shared.currentMouseScreen?.frame ?? NSScreen.main?.frame else { return origin }
        return clampToScreen(origin: origin, contentSize: contentSize, screenFrame: screenFrame)
    }

    func calculateSelectionOverlayOrigin(bounds: NSRect, screenFrame: NSRect, screenHeight: CGFloat, spacingX: CGFloat, spacingY: CGFloat, contentSize: NSSize) -> NSPoint {
        let cocoaPoint = AXAtomic.convertAXPointToCocoa(axPoint: bounds.origin, screenHeight: screenHeight)
        let origin = NSPoint(
            x: bounds.origin.x + screenFrame.origin.x - shadowPadding + spacingX,
            y: cocoaPoint.y + screenFrame.origin.y - shadowPadding + spacingY
        )
        return clampToScreen(origin: origin, contentSize: contentSize, screenFrame: screenFrame)
    }

    func calculatePointOverlayOrigin(point: NSPoint, contentSize: NSSize, screenFrame: NSRect, spacing: CGFloat) -> NSPoint {
        let origin = NSPoint(
            x: point.x - shadowPadding,
            y: point.y + spacing - shadowPadding
        )
        return clampToScreen(origin: origin, contentSize: contentSize, screenFrame: screenFrame)
    }

    func calculateCenterOverlayOrigin(contentSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let x = screenFrame.origin.x + (screenFrame.width - contentSize.width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - contentSize.height) / 2
        return NSPoint(x: x, y: y)
    }

    func moveAndUpdateExistingPanel(
        uuid: UUID,
        @ViewBuilder content: (_ panelId: UUID) -> some View,
        origin: NSPoint,
        contentSize _: NSSize,
        extraHeight: CGFloat
    ) {
        guard let panel = panels[uuid] else { return }

        let (hosting, actualSize) = createHostingViewAndGetSize(content: { content(uuid) })
        panel.contentView = hosting

        let newFrame = NSRect(
            origin: origin,
            size: NSSize(width: actualSize.width, height: actualSize.height + extraHeight)
        )

        if NSEqualPoints(panel.frame.origin, origin) {
            panel.setFrame(newFrame, display: true)
            return
        }
        panel.animations = ["frame": CASpringAnimation.createSpringFrameMoveAnimation(keyPath: "frame", fromValue: panel.frame, toValue: newFrame)]
        panel.animator().setFrame(newFrame, display: true)
    }

    func getValidSelectionBounds() -> (bounds: NSRect?, isExact: Bool) {
        if let bounds = getSelectionBounds(),
           bounds.width >= 1, bounds.height >= 1
        {
            return (bounds, true)
        }

        guard let mouseBounds = MouseContextService.shared.getMouseRect() else {
            return (nil, false)
        }

        log.info("Fallback: \(mouseBounds) \(String(describing: MouseContextService.shared.getMouseScreen()))")
        return (mouseBounds, false)
    }

    func getSelectionBounds() -> NSRect? {
        guard let element = AXElementAccessor.getFocusedElement(),
              let rangeValue: AXValue = AXElementAccessor.getAttributeValue(
                  element: element,
                  attribute: kAXSelectedTextRangeAttribute
              )
        else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }

        guard let boundsValue: AXValue = AXElementAccessor.getParameterizedAttributeValue(
            element: element,
            attribute: kAXBoundsForRangeParameterizedAttribute,
            parameter: rangeValue
        ) else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &rect) else { return nil }

        if range.length == 0 {
            rect.size.width = max(rect.size.width, 1)
        }

        log.info("range: \(range.location), \(range.length), boundsValue: \(boundsValue)")
        return NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    func createHostingViewAndGetSize(@ViewBuilder content: () -> some View) -> (
        hosting: AutoResizingHostingView<AnyView>, size: NSSize
    ) {
        let hosting = AutoResizingHostingView(rootView: AnyView(content().padding(shadowPadding)))
        let tempPanel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tempPanel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        return (hosting, hosting.fittingSize)
    }

    // Panel Size 变化时, 扩展的原点为左上角点
    // 处理向上展开的 panel 大小变化原点固定左下角
    func handlePanelSizeChange(uuid: UUID) {
        guard let panel = panels[uuid],
              let contentView = panel.contentView,
              panel.expandDirection == .up
        else { return }

        let oldFrame = panel.frame
        var newOrigin = oldFrame.origin

        // 面板拖动也会引起的 sizechange 事件
        guard abs((panel.initialOrigin?.x ?? 0) - newOrigin.x) < 1 else {
            return
        }

        newOrigin.y = panel.initialOrigin?.y ?? newOrigin.y
        let newFrame = NSRect(origin: newOrigin, size: contentView.fittingSize)
        panel.setFrame(newFrame, display: true, animate: false)
    }
}

private extension OverlayController {
    func setupScreenChangeListener() {
        ConnectionCenter.shared.$currentMouseScreen
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.handleScreenChanged(screen: screen)
            }
            .store(in: &cancellables)
    }

    func handleScreenChanged(screen: NSScreen?) {
        guard let screen else { return }
        for (_, panel) in panels {
            guard panel.isVisible,
                  panel.panelType?.canFollowScreenChange == true,
                  panel.wasDragged == false
            else { continue }
            updatePanelPositionForScreen(panel, screen: screen)
        }
    }

    func updatePanelPositionForScreen(_ panel: NSPanel, screen: NSScreen) {
        let statusPanel = StatusPanelManager.shared.getPanel()
        let statusSize = statusPanel.frame.size

        // 计算 StatusPanel 在新屏幕上位置
        let newStatusFrame = NSRect(
            x: screen.visibleFrame.origin.x + (screen.visibleFrame.width - statusSize.width) / 2,
            y: screen.visibleFrame.origin.y,
            width: statusSize.width,
            height: statusSize.height
        )
        let currentSize = panel.frame.size
        let newOrigin = calculateOverlayOrigin(
            statusFrame: newStatusFrame,
            contentSize: currentSize,
            spacing: 4,
            screenFrame: screen.frame
        )
        let newFrame = NSRect(origin: newOrigin, size: currentSize)

        panel.isUpdatingPosition = true
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                panel.setFrame(newFrame, display: true, animate: false)
                panel.isUpdatingPosition = false
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1.0
                }
            }
        )
    }
}
