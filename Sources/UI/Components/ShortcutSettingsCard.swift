import Combine
import SwiftUI

struct ShortcutSettingsState {
    var isVisible: Bool = false
    var opacity: Double = 0
}

// 单个按键显示组件
struct KeyCapView: View {
    let keyName: String
    
    var displayText: String {
        // 简化显示文本，提取符号
        if keyName.contains("Command") || keyName.contains("⌘") {
            "⌘"
        } else if keyName.contains("Option") || keyName.contains("⌥") {
            "⌥"
        } else if keyName.contains("Control") || keyName.contains("⌃") {
            "⌃"
        } else if keyName.contains("Shift") || keyName.contains("⇧") {
            "⇧"
        } else if keyName == "Space" {
            "Space"
        } else if keyName == "Return" {
            "↩"
        } else if keyName == "Delete" {
            "⌫"
        } else if keyName == "Escape" {
            "⎋"
        } else if keyName == "Tab" {
            "⇥"
        } else {
            keyName
        }
    }
    
    var body: some View {
        Text(displayText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1),
                    ),
            )
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
    }
}

// 可编辑的快捷键输入框
struct ShortcutInputField: View {
    let mode: RecordMode
    @Binding var keyCodes: [Int64]
    @State private var isEditing: Bool = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if keyCodes.isEmpty {
                    Text("点击设置")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    ForEach(Array(keyCodes.enumerated()), id: \.offset) { index, keyCode in
                        KeyCapView(keyName: KeyMapper.keyCodeToString(keyCode))
                        
                        if index < keyCodes.count - 1 {
                            Text("+")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                
                Spacer()
                
                if isEditing {
                    Text("按下快捷键...")
                        .font(.system(size: 10))
                        .foregroundColor(.blue.opacity(0.8))
                }
            }
            .frame(height: 24)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEditing ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isEditing ? Color.blue.opacity(0.6) : Color.white.opacity(0.2),
                                lineWidth: isEditing ? 2 : 1,
                            ),
                    ),
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditing else { return }
                startEditing()
            }
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .onAppear {
                setupEventListeners()
            }
        }
    }
    
    private func startEditing() {
        isEditing = true
        EventBus.shared.publish(.hotkeySettingStarted(mode: mode))
    }
    
    private func setupEventListeners() {
        // 监听快捷键更新事件（实时显示）
        EventBus.shared.events.receive(on: DispatchQueue.main)
            .sink { event in
                switch event {
                case .hotkeySettingUpdated(let eventMode, let combination):
                    guard eventMode == mode else { return }
                    let codes = combination.compactMap { KeyMapper.stringToKeyCodeMap[$0] }
                    keyCodes = codes
                    
                case .hotkeySettingResulted(let eventMode, _):
                    guard eventMode == mode else { return }
                    isEditing = false
                    
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}

struct ShortcutSettingsCard: View {
    let onClose: () -> Void
    @State private var normalKeyCodes: [Int64] = []
    @State private var commandKeyCodes: [Int64] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("快捷键设置")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(white: 0.15))
            
            // 主内容区域
            VStack(alignment: .leading, spacing: 20) {
                // 内容卡片
                VStack(alignment: .leading, spacing: 16) {
                    // 第一行：普通模式
                    VStack(alignment: .leading, spacing: 8) {
                        Text("普通模式")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        ShortcutInputField(mode: .normal, keyCodes: $normalKeyCodes)
                    }
                    
                    // 分隔线
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // 第二行：命令模式
                    VStack(alignment: .leading, spacing: 8) {
                        Text("命令模式")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        
                        ShortcutInputField(mode: .command, keyCodes: $commandKeyCodes)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            
            // 底部按钮区域
            HStack {
                Spacer()
                
                Button(action: onClose) {
                    Text("关闭")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
        .onAppear {
            // 加载快捷键配置
            normalKeyCodes = Config.NORMAL_KEY_CODES
            commandKeyCodes = Config.COMMAND_KEY_CODES
        }
    }
}
