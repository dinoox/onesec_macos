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
    var audioRecorder: AudioSinkNodeRecorder = .init()
    var keyEventProcessor: KeyEventProcessor = .init()

    /// 事件监听器
    private var eventTap: CFMachPort?
    /// 运行循环源
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    private var cancellables = Set<AnyCancellable>()

    init() {
        initializeEventHandler()
        initializeTapListener()
        log.info("InputController initialized")
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource, let runLoop {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }

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

        // 创建运行循环源
        runLoop = CFRunLoopGetCurrent()
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)

        // 启用事件监听器
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }

    private func buildEventMask() -> CGEventMask {
        var eventMask: UInt64 = 0

        // 监听所有按键事件类型，确保快捷键设置功能能检测到所有按键
        // 包括修饰键和普通键的所有事件类型
        eventMask |= (1 << CGEventType.flagsChanged.rawValue)
        eventMask |= (1 << CGEventType.keyDown.rawValue)
        eventMask |= (1 << CGEventType.keyUp.rawValue)

        // 监听鼠标移动事件，用于检测鼠标跨屏幕移动
        eventMask |= (1 << CGEventType.mouseMoved.rawValue)
        eventMask |= (1 << CGEventType.leftMouseDragged.rawValue)
        eventMask |= (1 << CGEventType.rightMouseDragged.rawValue)
        eventMask |= (1 << CGEventType.otherMouseDragged.rawValue)

        return CGEventMask(eventMask)
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        guard type != .tapDisabledByTimeout else {
            log.warning("CGEventType tapDisabledByTimeout")
            return Unmanaged.passUnretained(event)
        }

        // 处理鼠标移动事件
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
            || type == .otherMouseDragged
        {
            handleMouseEvent(event: event)
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        // 拦截快捷键的设置
        if keyEventProcessor.isHotkeySetting {
            keyEventProcessor.handleHotkeySettingEvent(type: type, event: event)
            return nil
        }

        // 正常处理按键监听
        switch keyEventProcessor.handlekeyEvent(type: type, event: event) {
        case .startMatch(let mode): startRecording(mode: mode)
        case .endMatch: stopRecording()
        case .modeUpgrade(let from, let to): modeUpgrade(from: from, to: to)
        case .throttled, .stillMatching, .notMatching:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    /// 处理鼠标移动事件，检测屏幕切换
    private func handleMouseEvent(event: CGEvent) {
        let mouseLocation = event.location

        guard  // 找到鼠标所在屏幕
            let newScreen = NSScreen.screens.first(where: { screen in
                NSMouseInRect(
                    NSPoint(x: mouseLocation.x, y: mouseLocation.y),
                    screen.frame,
                    false,
                )
            })
        else {
            return
        }

        let currentScreen = ConnectionCenter.shared.currentMouseScreen

        // 检测屏幕是否变化
        if currentScreen == nil || currentScreen != newScreen {
            ConnectionCenter.shared.currentMouseScreen = newScreen
            EventBus.shared.publish(.mouseScreenChanged(screen: newScreen))
        }
    }

    private func startRecording(mode: RecordMode) {
        guard ConnectionCenter.shared.isAuthed else {
            EventBus.shared.publish(.notificationReceived(.authTokenFailed))
            return
        }

        guard ConnectionCenter.shared.networkState == .available else {
            EventBus.shared.publish(.notificationReceived(.networkUnavailable))
            return
        }

        guard
            ConnectionCenter.shared.wssState == .connected
                || ConnectionCenter.shared.wssState == .manualDisconnected
        else {
            EventBus.shared.publish(.notificationReceived(.networkUnavailable))
            return
        }

        if ConnectionCenter.shared.wssState == .manualDisconnected {
            ConnectionCenter.shared.connectWss()
        }
        
        audioRecorder.startRecording(mode: mode)
    }

    private func stopRecording() {
        audioRecorder.stopRecording()
    }

    private func modeUpgrade(from: RecordMode, to: RecordMode) {
        if to == .normal {
            return
        }
        EventBus.shared.publish(.modeUpgraded(from: from, to: to))
    }
}

extension InputController {
    func initializeEventHandler() {
        EventBus.shared.events
            .sink { [weak self] event in
                switch event {
                case .hotkeySettingStarted(let mode):
                    self?.handleHotkeySettingStarted(mode: mode)
                case .hotkeySettingEnded(let mode, let hotkeyCombination):
                    self?.handleHotkeySettingEnded(mode: mode, hotkeyCombination: hotkeyCombination)
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
}
