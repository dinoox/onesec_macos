import AppKit
import Combine
import SwiftUI

struct StatusView: View {
    @State var volume: CGFloat = 0 // 音量值 (0-1)
    
    @State var recordState: RecordState = .idle
    @State var mode: RecordMode = .normal
    @State var showNotification: Bool = false
    
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
    
    var body: some View {
        ZStack {
            // 背景层 - 不响应鼠标事件
            VStack {
                Spacer()
                
                if showNotification {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: outerSize, height: outerSize)
                }
               
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: outerSize, height: outerSize)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .allowsHitTesting(false)
            
            // 内外圈层 - 只有圆形区域响应鼠标事件
            VStack {
                Spacer()
                
                if showNotification {
                    Color.clear
                        .frame(width: outerSize, height: outerSize)
                }
                
                HStack {
                    Spacer()
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
                    Spacer()
                }
            }
        }
        .onReceive(EventBus.shared.events) { event in
            switch event {
            case .volumeChanged(let volume):
                // 确保音量值在 0-1 范围内，防止内圈超过最大比例
                self.volume = min(1.0, max(0.0, CGFloat(volume)))
            case .recordingStarted(_, _, _, let recordMode):
                mode = recordMode
                recordState = .recording
            case .recordingStopped:
                recordState = .processing
            case .serverResultReceived:
                recordState = .idle
            case .modeUpgraded(_, let toMode, _):
                mode = toMode
            case .notificationReceived(let title, let content):
                showNotification = true
                log.info("title \(title)\n \(content)")
            default:
                break
            }
        }
    }
}
