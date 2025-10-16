//
//  VoiceInputManager.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Carbon
import Cocoa

/// 全局快捷键监听器
/// 负责监听配置的按键组合的按下和松开事件，控制录音的开始和停止
class VoiceInputController {
    /// 最大录音时长（秒）
    private let maxRecordingDuration: TimeInterval = 60.0

    private var audioRecorder: AudioSinkNodeRecorder = .init()

    /// 按键事件处理器
    private var keyEventProcessor: KeyEventProcessor?

    /// 事件监听器
    private var eventTap: CFMachPort?
    /// 运行循环源
    private var runLoopSource: CFRunLoopSource?

    init() {
        setupKeyEventProcessor()
        registerGlobalTapListener()
        Task {
            let circlePanel = await StatusPanelManager.shared.showPanel()

//            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
//                EventBus.shared.publish(.notification(title: "a", content: "v"))
//            }
        }
        log.info("VoiceInputManager init")
    }

    private func setupKeyEventProcessor() {
        keyEventProcessor = KeyEventProcessor(
            normalKeyCodes: [63], // Fn - 普通模式
            commandKeyCodes: [63, 55], // Fn + Command - 命令模式
        )
        log.info("按键事件处理器已初始化")
    }

    func didReceiveInitConfig(authToken: String?, hotkeyConfigs: [[String: Any]]?, timestamp: Int64) {
        if let hotkeyConfigs {
            for config in hotkeyConfigs {
                if let mode = config["mode"] as? String,
                   let hotkeyCombination = config["hotkey_combination"] as? [String]
                {
//                    updateHotkeyConfiguration(mode: mode, hotkeyCombination: hotkeyCombination)
                }
            }
        }

        registerGlobalTapListener()
    }

    private func registerGlobalTapListener() {
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(buildEventMask()),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<VoiceInputController>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque(),
        )

        // 创建运行循环源
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // 启用事件监听器
        CGEvent.tapEnable(tap: eventTap!, enable: true)
        log.info("全局快捷键监听器已启动")
    }

    private func buildEventMask() -> CGEventMask {
        var eventMask: UInt64 = 0

        // 监听所有按键事件类型，确保快捷键设置功能能检测到所有按键
        // 包括修饰键和普通键的所有事件类型
        eventMask |= (1 << CGEventType.flagsChanged.rawValue)
        eventMask |= (1 << CGEventType.keyDown.rawValue)
        eventMask |= (1 << CGEventType.keyUp.rawValue)
        // eventMask |= (1 << CGEventType.mouseMoved.rawValue)
        // eventMask |= (1 << CGEventType.leftMouseDragged.rawValue)
        // eventMask |= (1 << CGEventType.rightMouseDragged.rawValue)
        // eventMask |= (1 << CGEventType.otherMouseDragged.rawValue)

        return CGEventMask(eventMask)
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            log.warning("⚠️ 系统禁用了事件监听器: \(type == .tapDisabledByTimeout ? "超时" : "用户输入")")
            return nil
        }

        guard let keyEventProcessor else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 如果正在设置快捷键，先检查是否需要拦截
        if keyEventProcessor.isHotkeySetting {
            if keyEventProcessor.handleHotkeySettingEvent(type: type, event: event) {
                return nil
            }
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        // 使用KeyEventProcessor处理按键事件
        let keyEvent = keyEventProcessor.handlekeyEvent(type: type, event: event)

        switch keyEvent {
        case .startRecording: startRecording()
        case .stopRecording: stopRecording()
        case .modeUpgrade:
            log.info("modeUpgrade")
        case .continueRecording:
            log.info("continueRecording")
        case .noAction:
            break
        }

        // 返回原始事件，让其他应用也能接收到
        return Unmanaged.passUnretained(event)
    }

    private func startRecording() {
        let appInfo = ContextService.getAppInfo()
        audioRecorder.startRecording(appInfo: appInfo, focusContext: nil, focusElementInfo: nil, recordMode: .normal)
    }

    private func stopRecording() {
        audioRecorder.stopRecording()
    }
}
