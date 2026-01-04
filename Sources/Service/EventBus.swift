//
//  EventBus.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import AppKit
import Combine
import Foundation

enum AppEvent {
    case volumeChanged(volume: Float)
    case recordingStarted(mode: RecordMode)
    case recordingStopped(isRecordingStarted: Bool = true, shouldSetResponseTimer: Bool = true)
    case recordingCancelled
    case recordingConfirmed
    //
    case recordingCacheStarted(mode: RecordMode)
    case recordingCacheTimeout
    case recordingInterrupted
    //
    case audioDataReceived(data: Data)
    case serverResultReceived(summary: String, interactionID: String, processMode: String, polishedText: String)
    case terminalLinuxChoice(bundleID: String, appName: String, endpointIdentifier: String, commands: [LinuxCommand])
    case modeUpgraded(from: RecordMode, to: RecordMode)
    case notificationReceived(NotificationMessageType)
    //
    case userDataUpdated(UserDataUpdateType)
    //
    case hotkeySettingStarted(mode: RecordMode)
    case hotkeySettingEnded(mode: RecordMode)
    case hotkeySettingUpdated(mode: RecordMode, hotkeyCombination: [String])
    case hotkeySettingResulted(mode: RecordMode, hotkeyCombination: [String], isConflict: Bool = false)
    //
    case hotkeyDetectStarted
    case hotkeyDetectEnded
    case hotkeyDetectUpdated(hotkeyCombination: [String], isCompleted: Bool)
    //
    case hotWordAddRequested(word: String)
    //
    case mouseScreenChanged(screen: NSScreen)
    case recordingContextUpdated(context: AppContext)
    case audioDeviceChanged
    case userAudioSaved(sessionID: String, filename: String)
}

class EventBus: @unchecked Sendable {
    static let shared = EventBus()

    let eventSubject = PassthroughSubject<AppEvent, Never>()
    private let lock = NSLock()

    // 发布事件
    func publish(_ event: AppEvent) {
        lock.lock()
        defer { lock.unlock() }
        eventSubject.send(event)
    }

    // 订阅所有
    lazy var events: AnyPublisher<AppEvent, Never> = eventSubject.share().eraseToAnyPublisher()

    func subscribe<T>(to _: T.Type) -> AnyPublisher<T, Never> {
        eventSubject.share()
            .compactMap { event in
                if case let loginEvent as T = event {
                    return loginEvent
                }
                return nil
            }
            .eraseToAnyPublisher()
    }
}

extension EventBus {
    var recordingSessionEnded: AnyPublisher<Void, Never> {
        eventSubject.share()
            .compactMap { event in
                switch event {
                case .serverResultReceived,
                     .notificationReceived(.serverTimeout),
                     .terminalLinuxChoice:
                    return ()
                default:
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
}
