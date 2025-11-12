import Combine
import SwiftUI

@MainActor
class OverlayController {
    static let shared = OverlayController()

    private var panels: [UUID: NSPanel] = [:]
    private let shadowPadding: CGFloat = 50
    private let statusBarHeight: CGFloat = 36
    private let defaultSpacing: CGFloat = 4

    private init() {}

    @discardableResult
    func showOverlay(@ViewBuilder content: (_ panelId: UUID) -> some View, extraHeight: CGFloat = 0) -> UUID {
        let uuid = UUID()
        let statusFrame = StatusPanelManager.shared.getPanelFrame()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        let origin = calculateOverlayOrigin(
            statusFrame: statusFrame,
            contentSize: contentSize,
            spacing: defaultSpacing
        )

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight)
        setupPanel(panel, hosting: hosting)
        animateFadeIn(panel)

        panels[uuid] = panel
        return uuid
    }

    func updateContent(uuid: UUID, @ViewBuilder content: () -> some View) {
        guard let panel = panels[uuid] else { return }

        let statusFrame = StatusPanelManager.shared.getPanelFrame()
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
    func showOverlayAboveSelection(@ViewBuilder content: (_ panelId: UUID) -> some View, extraHeight: CGFloat = 0) -> UUID? {
        guard let bounds = getValidSelectionBounds(),
              let screen = MouseContextService.shared.getMouseScreen() ?? NSScreen.main
        else {
            return nil
        }

        let uuid = UUID()
        let (hosting, contentSize) = createHostingViewAndGetSize(content: { content(uuid) })

        let origin = calculateSelectionOverlayOrigin(
            bounds: bounds,
            screenFrame: screen.frame,
            screenHeight: screen.frame.height,
            spacing: 14
        )

        let panel = createPanel(origin: origin, size: contentSize, extraHeight: extraHeight)
        setupPanel(panel, hosting: hosting)
        panel.isMovableByWindowBackground = true
        animateFadeIn(panel)

        panels[uuid] = panel
        return uuid
    }

    @discardableResult
    func showOverlayAbovePoint(point: NSPoint, @ViewBuilder content: (_ panelId: UUID) -> some View) -> UUID? {
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

        let panel = createPanel(origin: origin, size: contentSize)
        setupPanel(panel, hosting: hosting)
        panel.isMovableByWindowBackground = true
        animateFadeIn(panel)

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
        panel.makeKeyAndOrderFront(nil)
    }

    func animateFadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0.0
        panel.animations = ["alphaValue": createSpringFadeInAnimation()]
        panel.animator().alphaValue = 1.0
    }

    func calculateOverlayOrigin(statusFrame: NSRect, contentSize: NSSize, spacing: CGFloat) -> NSPoint {
        NSPoint(
            x: statusFrame.origin.x + (statusFrame.width - contentSize.width) / 2,
            y: statusFrame.origin.y + statusBarHeight + spacing - shadowPadding
        )
    }

    func calculateSelectionOverlayOrigin(bounds: NSRect, screenFrame: NSRect, screenHeight: CGFloat, spacing: CGFloat) -> NSPoint {
        let cocoaPoint = AXAtomic.convertAXPointToCocoa(axPoint: bounds.origin, screenHeight: screenHeight)
        return NSPoint(
            x: bounds.origin.x + screenFrame.origin.x - shadowPadding + spacing - 6,
            y: cocoaPoint.y + screenFrame.origin.y - shadowPadding + spacing
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

    func getValidSelectionBounds() -> NSRect? {
        if let bounds = getSelectionBounds(),
           bounds.width >= 1, bounds.height >= 1
        {
            return bounds
        }

        guard let mouseBounds = MouseContextService.shared.getMouseRect() else {
            return nil
        }

        log.info("Fallback: \(mouseBounds) \(String(describing: MouseContextService.shared.getMouseScreen()))")
        return mouseBounds
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

        log.info("rangeValue: \(rangeValue), range: \(range.location), \(range.length), boundsValue: \(boundsValue)")
        return NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    func createSpringFadeInAnimation() -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: "alphaValue")
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.mass = 1.0
        animation.stiffness = 300.0
        animation.damping = 20.0
        animation.initialVelocity = 0.0
        animation.duration = animation.settlingDuration
        return animation
    }

    func createHostingViewAndGetSize(@ViewBuilder content: () -> some View) -> (
        hosting: NSHostingView<AnyView>, size: NSSize
    ) {
        let hosting = NSHostingView(rootView: AnyView(content().padding(shadowPadding)))
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
}
