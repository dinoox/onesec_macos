//
//  VoiceInputManager.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Carbon
import Cocoa
import Combine

/// 全局 Input 控制器
/// 负责监听配置的按键组合的按下和松开事件，控制录音的开始和停止
class InputController {
    private var audioRecorder: AudioSinkNodeRecorder = .init()
    private var keyEventProcessor: KeyEventProcessor = .init()

    /// 事件监听器
    private var eventTap: CFMachPort?
    /// 运行循环源
    private var runLoopSource: CFRunLoopSource?
    /// 保存创建时的 run loop
    private var runLoop: CFRunLoop?

    private var cancellables = Set<AnyCancellable>()

    init() {
        initializeEventHandler()
        initializeTapListener()
        log.info("InputController initialized")
    }

    deinit {
        // 禁用事件监听器
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        // 从运行循环中移除源
        if let runLoopSource = runLoopSource, let runLoop = runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }

        // 清空引用
        eventTap = nil
        runLoopSource = nil
        runLoop = nil
        log.info("InputController deinitialized")
    }

    private func initializeTapListener() {
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(buildEventMask()),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let monitor = Unmanaged<InputController>.fromOpaque(refcon!).takeUnretainedValue()
                return monitor.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque(),
        )

        // 保存当前运行循环
        runLoop = CFRunLoopGetCurrent()

        // 创建运行循环源
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)

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

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        guard type != .tapDisabledByTimeout else {
            log.warning("CGEventType tapDisabledByTimeout")
            return nil
        }

        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return nil
        }

        // 拦截快捷键的设置
        if keyEventProcessor.isHotkeySetting {
            keyEventProcessor.handleHotkeySettingEvent(type: type, event: event)
            return nil
        }

        // 正常处理按键监听
        switch keyEventProcessor.handlekeyEvent(type: type, event: event) {
        case .startMatch(let mode):
            startRecording(mode: mode)
        case .endMatch:
            stopRecording()
        case .modeUpgrade(let from, let to):
            modeUpgrade(from: from, to: to)
        case .stillMatching, .notMatching:
            break
        }

        // 返回原始事件
        return Unmanaged.passUnretained(event)
    }

    private func startRecording(mode: RecordMode) {
        let appInfo = ContextService.getAppInfo()
        audioRecorder.startRecording(
            appInfo: appInfo, focusContext: nil, focusElementInfo: nil, recordMode: mode,
        )
    }

    private func stopRecording() {
        audioRecorder.stopRecording()
    }

    private func modeUpgrade(from: RecordMode, to: RecordMode) {
        if to == .normal {
            return
        }
        EventBus.shared.publish(.modeUpgraded(from: from, to: to, focusContext: nil))
    }
}

extension InputController {
    func initializeEventHandler() {
        EventBus.shared.events
            .sink { [weak self] event in
                switch event {
                case .userConfigChanged(let authToken, let hotkeyConfigs):
                    self?.handleConfigInitialized(
                        authToken: authToken, hotkeyConfigs: hotkeyConfigs,
                    )
                case .hotkeySettingStarted(let mode):
                    self?.handleHotkeySettingStarted(mode: mode)
                case .hotkeySettingEnded(let mode, let hotkeyCombination):
                    self?.handleHotkeySettingEnded(mode: mode, hotkeyCombination: hotkeyCombination)
                case .serverResultReceived(let summary, _):
                    ContextService.pasteTextToActiveApp(summary)
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func handleHotkeySettingStarted(mode: RecordMode) {
        keyEventProcessor.startHotkeySetting(mode: mode)
    }

    private func handleHotkeySettingEnded(mode: RecordMode, hotkeyCombination: [String]) {
        keyEventProcessor.endHotkeySetting()
        Config.saveHotkeySetting(mode: mode, hotkeyCombination: hotkeyCombination)
    }

    private func handleConfigInitialized(authToken: String, hotkeyConfigs: [[String: Any]]) {
        Config.AUTH_TOKEN = authToken

        for config in hotkeyConfigs {
            guard let mode = config["mode"] as? String,
                let hotkeyCombination = config["hotkey_combination"] as? [String]
            else {
                continue
            }

            Config.saveHotkeySetting(
                mode: mode == "normal" ? .normal : .command, hotkeyCombination: hotkeyCombination,
            )
        }
    }
}
