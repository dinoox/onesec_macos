//
//  InputController.swift
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
    private let eventQueue = DispatchQueue(label: "com.onesec.inputcontroller", qos: .userInteractive)

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
            tap: .cghidEventTap,
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
            CGEvent.tapEnable(tap: eventTap!, enable: true)
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
            return Unmanaged.passUnretained(event)
        }

        eventQueue.async { [weak self] in
            self?.handleCGEventInternal(proxy: proxy, type: type, event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleCGEventInternal(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        // 处理鼠标移动事件
        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
            || type == .otherMouseDragged
        {
            handleMouseEvent(event: event)
            return
        }

        // 过滤非物理按键事件 (程序合成按键)
        let sourceStateID = event.getIntegerValueField(.eventSourceStateID)
        if sourceStateID != 1 { // 1 = kCGEventSourceStateHIDSystemState
            return
        }

        // 拦截快捷键的设置
        if keyEventProcessor.isHotkeySetting {
            keyEventProcessor.handleHotkeySettingEvent(type: type, event: event)
            return
        }

        // 正常处理按键监听
        switch keyEventProcessor.handlekeyEvent(type: type, event: event) {
        case let .startMatch(mode): startRecording(mode: mode)
        case .endMatch: stopRecording()
        case let .modeUpgrade(from, to): modeUpgrade(from: from, to: to)
        case .throttled, .stillMatching, .notMatching:
            break
        }
    }

    /// 处理鼠标移动事件，检测屏幕切换
    private func handleMouseEvent(event: CGEvent) {
        let mouseLocation = event.location

        guard // 找到鼠标所在屏幕
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

        Task { @MainActor in
            self.audioRecorder.startRecording(mode: mode)
        }
    }

    private func stopRecording() {
        Task { @MainActor in
            self.audioRecorder.stopRecording()
        }
    }

    private func modeUpgrade(from _: RecordMode, to: RecordMode) {
        if to == .command {
            audioRecorder.handleModeUpgrade()
        }
    }
}

extension InputController {
    func initializeEventHandler() {
        EventBus.shared.events
            .sink { [weak self] event in
                switch event {
                case let .hotkeySettingStarted(mode):
                    self?.keyEventProcessor.startHotkeySetting(mode: mode)
                case .hotkeySettingEnded, .hotkeySettingResulted:
                    self?.keyEventProcessor.endHotkeySetting()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}
