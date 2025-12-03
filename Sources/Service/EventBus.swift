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
    case recordingStarted(recordMode: RecordMode)
    case recordingStopped
    case audioDataReceived(data: Data)
    case serverResultReceived(summary: String, interactionID: String, processMode: TextProcessMode, polishedText: String)
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
    case hotWordAddRequested(word: String)
    //
    case mouseScreenChanged(screen: NSScreen)
    case recordingContextUpdated(context: AppContext)
    case audioDeviceChanged
}

class EventBus: @unchecked Sendable {
    static let shared = EventBus()
    let eventSubject = PassthroughSubject<AppEvent, Never>()

    // 发布事件
    func publish(_ event: AppEvent) {
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
                     .notificationReceived(.recordingTimeout),
                     .terminalLinuxChoice:
                    return ()
                default:
                    return nil
                }
            }
            .eraseToAnyPublisher()
    }
}
