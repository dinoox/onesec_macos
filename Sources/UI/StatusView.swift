import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var volume: CGFloat = 0 // 音量值 (0-1)
    
    @State var recordState: RecordState = .idle
    @State var mode: RecordMode = .normal
    
    let minInnerRatio: CGFloat = 0.2 // 内圆最小为外圆的20%
    let maxInnerRatio: CGFloat = 0.7 // 内圆最大为外圆的70%
    
    private var modeColor: Color {
        mode == .normal ? auroraGreen : starlightYellow
    }
    
    // 外圆大小
    private var outerSize: CGFloat {
        switch recordState {
        case .idle:
            20
        case .recording, .processing:
            25
        default:
            20
        }
    }
    
    private var innerSize: CGFloat {
        let ratio = minInnerRatio + (maxInnerRatio - minInnerRatio) * volume
        return outerSize * ratio
    }
    
    // 外圆背景颜色
    private var outerBackgroundColor: Color {
        switch recordState {
        case .idle:
            Color.clear
        case .recording, .processing:
            Color.black
        default:
            Color.clear
        }
    }
    
    // 边框颜色
    private var borderColor: Color {
        switch recordState {
        case .idle:
            Color(hex: "#888888B2")
        case .recording:
            Color(hex: "#888888B2")
        default:
            Color.white.opacity(0.8)
        }
    }
    
    @State var showNotification: Bool = false
    @State var notificationOpacity: Double = 0 // 控制通知卡片的透明度
    @State var notificationTitle: String = ""
    @State var notificationContent: String = ""
    
    private var notificationCard: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Image.systemSymbol("bell.fill")
                    .font(.system(size: 20))
                    .foregroundColor(modeColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(notificationTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                // 内容
                Text(notificationContent)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1),
                ),
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 0)
    }
    
    // 显示通知的方法
    private func showNotificationMessage(title: String, content: String, autoHide: Bool = true) {
        notificationTitle = title
        notificationContent = content
        
        Task {
            // try? await Task.sleep(nanoseconds: 900_000_000)
            
            // 第一步：立即显示通知占位（触发窗口 resize，但通知是透明的）
            showNotification = true
            notificationOpacity = 0
            
            // 第二步：等待布局和 resize 完成
            try? await Task.sleep(nanoseconds: 100_000_000) // 50ms
            
            // 第三步：淡入通知卡片（此时窗口已经 resize 完成，不会影响布局）
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                notificationOpacity = 1
            }
            
            if autoHide {
                // 再等3秒后隐藏
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    notificationOpacity = 0
                }
                
                try? await Task.sleep(nanoseconds: 300_000_000)
                showNotification = false
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 通知区域 - 始终占位，通过 opacity 控制可见性
            if showNotification {
                // Circle()
                //     .fill(Color.red)
                //     .frame(width: outerSize, height: outerSize)
                //     .opacity(notificationOpacity)
                notificationCard.opacity(notificationOpacity)
                
                Spacer().frame(height: 8)
            }
            
            // 状态指示器 - 固定在这里
            ZStack {
                // 外圆背景
                Circle()
                    .fill(outerBackgroundColor)
                    .frame(width: outerSize, height: outerSize)
                
                // 外圆
                Circle()
                    .strokeBorder(borderColor, lineWidth: 1)
                    .frame(width: outerSize, height: outerSize)
                
                // 内圆
                Group {
                    if recordState == .idle {
                        Circle()
                            .fill(Color(hex: "#888888B2"))
                            .frame(width: innerSize, height: innerSize)
                    } else if recordState == .recording {
                        Circle()
                            .fill(modeColor)
                            .frame(width: innerSize, height: innerSize)
                    } else if recordState == .processing {
                        Spinner(
                            color: modeColor,
                            size: 13,
                        )
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: innerSize)
            }
            .frame(width: outerSize, height: outerSize)
            .contentShape(Circle())
            .offset(y: recordState == .idle ? 0 : -4)
           .animation(.spring(response: 0.3, dampingFraction: 0.7), value: recordState)
        }.padding([.top, .leading, .trailing], 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(
                EventBus.shared.events
                    .receive(on: DispatchQueue.main),
            ) { event in
                switch event {
                case .volumeChanged(let volume):
                    // 确保音量值在 0-1 范围
                    self.volume = min(1.0, max(0.0, CGFloat(volume)))
                case .recordingStarted(_, _, _, let recordMode):
                    mode = recordMode
                    recordState = .recording
                case .recordingStopped:
                    recordState = .processing
                    volume = 0
                case .serverResultReceived:
                    recordState = .idle
                case .modeUpgraded(let from, let to, _):
                    log.info("statusView receive modeUpgraded \(from) \(to)")
                    if to == .command {
                        mode = to
                    }
                case .notificationReceived(let notificationType):
                    log.info("notificationReceived: \(notificationType)")
                    showNotificationMessage(title: notificationType.title, content: notificationType.content)
                case .serverTimedout:
                    showNotificationMessage(title: "服务超时", content: "服务器响应超时，请稍后重试")
                default:
                    break
                }
            }
    }
}
