import AppKit
import Combine
import SwiftUI

// 自定义 HostingView，监听大小变化
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
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false

        // 设置内容视图
        let hostingView = AutoResizingHostingView(rootView: StatusView())
        hostingView.onSizeChanged = { [weak self] in
            self?.resizeToFitContent()
        }
        self.contentView = hostingView

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
        guard self.isVisible, let screen else { return }
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
            }
        )
    }

    /// 计算底部居中的 frame
    /// - Parameters:
    ///   - size: 窗口尺寸
    ///   - screen: 目标屏幕，如果不指定则使用主屏幕
    /// - Returns: 计算好的 frame，如果屏幕不可用则返回 nil
    private func calculateBottomCenterFrame(for size: NSSize, on screen: NSScreen? = nil) -> NSRect?
    {
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

        // log.debug("size change: width \(newSize.width) height: \(newSize.height)")

        lastContentSize = newSize

        let contentRect = NSRect(origin: .zero, size: newSize)
        let frameSize = frameRect(forContentRect: contentRect).size

        // 计算底部居中的 frame，使用当前屏幕
        guard
            let newFrame = calculateBottomCenterFrame(
                for: frameSize, on: ConnectionCenter.shared.currentMouseScreen)
        else { return }

        isResizing = true
        setFrame(newFrame, display: true, animate: false)
        isResizing = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        // logFrameChange(from: frame, to: frameRect)
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(
        _ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool
    ) {
        // logFrameChange(from: frame, to: frameRect)
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }

    private func logFrameChange(from oldFrame: NSRect, to newFrame: NSRect) {
        let sizeChanged =
            abs(oldFrame.size.width - newFrame.size.width) > 1.0
            || abs(oldFrame.size.height - newFrame.size.height) > 1.0

        if sizeChanged {
            if isResizing {
                log.warning(
                    "FRAME SIZE: | \(oldFrame.origin) \(oldFrame.size) to \(newFrame.origin) \(newFrame.size) [由用户代码触发]"
                )
            } else {
                log.warning(
                    "FRAME SIZE: | \(oldFrame.origin) \(oldFrame.size) to \(newFrame.origin) \(newFrame.size) [由 NSHostingView 自动触发]"
                )
            }
        }
    }
}

@MainActor
class StatusPanelManager {
    static let shared = StatusPanelManager()

    private var panel: StatusPanel?
    private init() {}

    func showPanel() {
        if panel == nil {
            panel = StatusPanel()
            panel?.alphaValue = 0
        }

        panel?.orderFrontRegardless()

        // 淡入
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1.0
        }
    }

    func hidePanel() {
        // 淡出
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel?.animator().alphaValue = 0
            },
            completionHandler: {
                self.panel?.orderOut(nil)
            },
        )
    }

    /// 获取 StatusPanel 的 frame
    func getPanelFrame() -> NSRect? {
        return panel?.frame
    }
}
