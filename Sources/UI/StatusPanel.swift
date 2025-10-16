import AppKit
import Combine
import SwiftUI

class StatusPanel: NSPanel {
    var panelSize = NSSize(width: 200, height: 30)
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
        )
        
        // 设置窗口属性
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        
        // 设置内容视图
        self.contentView = NSHostingView(rootView: StatusView())
        
        positionAtBottomCenter()
//        Task { @MainActor
//            EventBus.shared.events
//                .sink { [weak self] event in
//                    guard let self else { return }
//
//                    switch event {
//                    case .notification(let title, let content):
//                        // 调整窗口大小为 130 高度
//                        adjustPanelHeight()
//
//                    default:
//                        break
//                    }
//                }
//                .store(in: &cancellables)
//        }
    }
    
    func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        
        let screenRect = screen.visibleFrame
        
        // 计算x坐标（屏幕水平居中）
        let x = screenRect.origin.x + (screenRect.width - panelSize.width) / 2
        
        // 计算y坐标（位于 Dock 上方）
        let spacing: CGFloat = 5 // 与 Dock 的间距
        let y = screenRect.origin.y + spacing
        
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    func adjustPanelHeight() {
        let newFrame = NSRect(x: frame.origin.x,
                              y: frame.origin.y,
                              width: 200,
                              height: 130)

        setFrame(newFrame, display: true, animate: false)
    }
    
    override var canBecomeKey: Bool {
        true
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        }, completionHandler: {
            self.panel?.orderOut(nil)
        })
    }
    
    func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel()
        }
    }
}
