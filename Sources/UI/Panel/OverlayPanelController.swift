import Combine
import ObjectiveC
import SwiftUI

enum PanelType {
    case translate
    case command
    case notification
}

enum ExpandDirection {
    case up
    case down
}

@MainActor
class OverlayController {
    static let shared = OverlayController()

    private var panels: [UUID: NSPanel] = [:]
    private let shadowPadding: CGFloat = 40
    private let statusBarHeight: CGFloat = 36
    private let defaultSpacing: CGFloat = 4

    @discardableResult
    func showOverlay(@ViewBuilder content: (_ panelId: UUID) -> some View, spacingX _: CGFloat = 0, spacingY _: CGFloat = 0, extraHeight: CGFloat = 0, panelType: PanelType? = nil) -> UUID {
        let statusFrame = StatusPanelManager.shared.getPanel().frame

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        let origin = calculateOverlayOrigin(
            statusFrame: statusFrame,
            contentSize: contentSize,
            spacing: defaultSpacing
        )

        // 如果指定了 panelType，尝试找到现有的同类型 panel
        if let panelType = panelType, let existingUUID = findPanelByType(panelType) {
            moveAndUpdateExistingPanel(
                uuid: existingUUID,
                content: content,
                origin: origin,
                contentSize: contentSize,
                extraHeight: extraHeight
            )

            return existingUUID
        }

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight)
        setupPanel(panel, hosting: hosting)
        animateFadeIn(panel)

        panel.panelType = panelType
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
        panel.close()
        panels.removeValue(forKey: uuid)
    }

    func hideAllOverlays() {
        panels.keys.forEach { hideOverlay(uuid: $0) }
    }

    private func hideOverlaysByPanelType(_ panelType: PanelType) {
        let uuidsToHide = panels.compactMap { uuid, panel in
            panel.panelType == panelType ? uuid : nil
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
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            hideOverlay(uuid: uuid)
        }
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
            spacingY: isExactBounds ? 0 : spacingY
        )

        if let panelType = panelType, let existingUUID = findPanelByType(panelType) {
            moveAndUpdateExistingPanel(
                uuid: existingUUID,
                content: content,
                origin: origin,
                contentSize: contentSize,
                extraHeight: extraHeight
            )

            return existingUUID
        }

        hosting.onSizeChanged = { [weak self] in
            self?.handlePanelSizeChange(uuid: uuid)
        }

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight)
        setupPanel(panel, hosting: hosting)

        animateFadeIn(panel)

        panel.panelType = panelType
        panel.expandDirection = expandDirection
        panel.isMovableByWindowBackground = true
        panel.initialOriginY = origin.y
        panels[uuid] = panel
        return uuid
    }

    @discardableResult
    func showOverlayAbovePoint(point: NSPoint, @ViewBuilder content: (_ panelId: UUID) -> some View, extraHeight: CGFloat = 0, panelType: PanelType? = nil, expandDirection: ExpandDirection? = nil) -> UUID? {
        if let panelType = panelType {
            hideOverlaysByPanelType(panelType)
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

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight)
        setupPanel(panel, hosting: hosting)
        animateFadeIn(panel)

        panel.panelType = panelType
        panel.isMovableByWindowBackground = true
        panel.expandDirection = expandDirection
        panel.initialOriginY = origin.y
        panels[uuid] = panel
        return uuid
    }
}

// MARK: - Private Helpers

private extension OverlayController {
    func createPanel(origin: NSPoint, size: NSSize, extraHeight: CGFloat = 0) -> NSPanel {
        NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: size.width, height: size.height + extraHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }

    func setupPanel(_ panel: NSPanel, hosting: NSHostingView<some View>) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.contentView = hosting
        panel.orderFront(nil)
    }

    func animateFadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0.0
        panel.animations = ["alphaValue": CASpringAnimation.createSpringFadeInAnimation(keyPath: "alphaValue")]
        panel.animator().alphaValue = 1.0
    }

    func calculateOverlayOrigin(statusFrame: NSRect, contentSize: NSSize, spacing: CGFloat) -> NSPoint {
        NSPoint(
            x: statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2,
            y: statusFrame.origin.y + statusBarHeight + spacing - shadowPadding
        )
    }

    func calculateSelectionOverlayOrigin(bounds: NSRect, screenFrame: NSRect, screenHeight: CGFloat, spacingX: CGFloat, spacingY: CGFloat) -> NSPoint {
        let cocoaPoint = AXAtomic.convertAXPointToCocoa(axPoint: bounds.origin, screenHeight: screenHeight)
        return NSPoint(
            x: bounds.origin.x + screenFrame.origin.x - shadowPadding + spacingX,
            y: cocoaPoint.y + screenFrame.origin.y - shadowPadding + spacingY
        )
    }

    func calculatePointOverlayOrigin(point: NSPoint, contentSize: NSSize, screenFrame: NSRect, spacing: CGFloat) -> NSPoint {
        var x = point.x - shadowPadding
        let y = point.y + spacing - shadowPadding

        let minX = screenFrame.origin.x
        let maxX = screenFrame.origin.x + screenFrame.width - contentSize.width
        x = max(minX, min(x, maxX))

        return NSPoint(x: x, y: y)
    }

    private func moveAndUpdateExistingPanel(
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
    private func handlePanelSizeChange(uuid: UUID) {
        guard let panel = panels[uuid],
              let contentView = panel.contentView,
              panel.expandDirection == .up else { return }

        let oldFrame = panel.frame
        var newOrigin = oldFrame.origin

        newOrigin.y = panel.initialOriginY ?? newOrigin.y

        let newFrame = NSRect(origin: newOrigin, size: contentView.fittingSize)
        panel.setFrame(newFrame, display: true, animate: false)
    }
}

extension NSPanel {
    private static var panelTypeKey: UInt8 = 0
    private static var expandDirectionKey: UInt8 = 1
    private static var initialOriginYKey: UInt8 = 2

    var panelType: PanelType? {
        get {
            return objc_getAssociatedObject(self, &Self.panelTypeKey) as? PanelType
        }
        set {
            objc_setAssociatedObject(self, &Self.panelTypeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var expandDirection: ExpandDirection? {
        get {
            return objc_getAssociatedObject(self, &Self.expandDirectionKey) as? ExpandDirection
        }
        set {
            objc_setAssociatedObject(self, &Self.expandDirectionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var initialOriginY: CGFloat? {
        get {
            return objc_getAssociatedObject(self, &Self.initialOriginYKey) as? CGFloat
        }
        set {
            objc_setAssociatedObject(self, &Self.initialOriginYKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
