import AppKit
import Combine
import SwiftUI

// 自定义 HostingView 监听大小变化
class AutoResizingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChanged: (() -> Void)?

    override func layout() {
        super.layout()
        onSizeChanged?()
    }
}

class StatusPanel: NSPanel {
    private var resizeWorkItem: DispatchWorkItem?
    private var lastContentSize: NSSize = .zero
    private var isResizing = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )

        // 设置窗口属性
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true

        // 设置内容视图
        let hostingView = AutoResizingHostingView(rootView: StatusView())
        hostingView.onSizeChanged = { [weak self] in
            self?.resizeToFitContent()
        }
        contentView = hostingView
        becomeKey()

        // 订阅屏幕切换事件
        setupScreenChangeListener()
    }

    private func setupScreenChangeListener() {
        ConnectionCenter.shared.$currentMouseScreen
            .dropFirst()
            .sink { [weak self] screen in
                self?.handleScreenChanged(screen: screen)
            }
            .store(in: &cancellables)
    }

    /// 处理屏幕切换事件
    private func handleScreenChanged(screen: NSScreen?) {
        guard isVisible, let screen else { return }
        updatePositionForScreen(screen)
    }

    /// 更新面板位置到指定屏幕
    private func updatePositionForScreen(_ screen: NSScreen) {
        let currentSize = frame.size
        guard let newFrame = calculateBottomCenterFrame(for: currentSize, on: screen) else {
            return
        }

        // 先淡出
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            },
            completionHandler: {
                // 更新位置
                self.setFrame(newFrame, display: true, animate: false)

                // 再淡入
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.animator().alphaValue = 1.0
                }
            },
        )
    }

    /// 计算底部居中的 frame
    /// - Parameters:
    ///   - size: 窗口尺寸
    ///   - screen: 目标屏幕，如果不指定则使用主屏幕
    /// - Returns: 计算好的 frame，如果屏幕不可用则返回 nil
    private func calculateBottomCenterFrame(for size: NSSize, on screen: NSScreen? = nil) -> NSRect? {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen else { return nil }

        let screenRect = targetScreen.visibleFrame

        // 计算 x 坐标（屏幕水平居中）
        let x = screenRect.origin.x + (screenRect.width - size.width) / 2

        // 计算 y 坐标（位于 Dock 上方）
        let y = screenRect.origin.y

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func resizeToFitContent() {
        guard !isResizing, let contentView else { return }

        contentView.layoutSubtreeIfNeeded()
        let newSize = contentView.fittingSize

        // 检查尺寸是否真的变化（允许 1 像素的误差）
        let sizeChanged =
            abs(newSize.width - lastContentSize.width) > 1.0
                || abs(newSize.height - lastContentSize.height) > 1.0

        guard sizeChanged else { return }

        lastContentSize = newSize

        let contentRect = NSRect(origin: .zero, size: newSize)
        let frameSize = frameRect(forContentRect: contentRect).size

        // 计算底部居中的 frame
        guard
            let newFrame = calculateBottomCenterFrame(
                for: frameSize, on: ConnectionCenter.shared.currentMouseScreen,
            )
        else { return }

        isResizing = true
        setFrame(newFrame, display: true, animate: false)
        isResizing = false
    }

    override var canBecomeKey: Bool {
        true
    }
}

@MainActor
class StatusPanelManager {
    static let shared = StatusPanelManager()

    private let panel: StatusPanel

    private init() {
        panel = StatusPanel()
        panel.alphaValue = 0
    }

    func showPanel() {
        panel.orderFrontRegardless()

        // 淡入
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }

    func hidePanel() {
        // 淡出
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                self.panel.orderOut(nil)
            },
        )
    }

    func ignoresMouseEvents(ignore: Bool = true) {
        panel.ignoresMouseEvents = ignore
        makeKeyPanel()
    }

    func getPanel() -> NSPanel {
        panel
    }

    func makeKeyPanel(completion: (() -> Void)? = nil) {
        panel.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            completion?()
        }
    }
}
