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
    case recordingStarted(appInfo: AppInfo?, focusContext: FocusContext?, focusElementInfo: FocusElementInfo?, recordMode: RecordMode)
    case recordingStopped
    case audioDataReceived(data: Data)
    case serverResultReceived(summary: String, serverTime: Int?)
    case modeUpgraded(from: RecordMode, to: RecordMode, focusContext: FocusContext?)
    case notificationReceived(NotificationMessageType)
    //
    case userConfigUpdated(authToken: String, hotkeyConfigs: [[String: Any]])
    //
    case hotkeySettingStarted(mode: RecordMode)
    case hotkeySettingEnded(mode: RecordMode, hotkeyCombination: [String])
    case hotkeySettingUpdated(mode: RecordMode, hotkeyCombination: [String])
    case hotkeySettingResulted(mode: RecordMode, hotkeyCombination: [String], isConflict: Bool = false)
    //
    case mouseScreenChanged(screen: NSScreen)
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

    func subscribe<T>(to eventType: T.Type) -> AnyPublisher<T, Never> {
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
    var volumeChanged: AnyPublisher<Float, Never> {
        eventSubject.share()
            .compactMap { event in
                guard case .volumeChanged(let volume) = event else { return nil }
                return volume
            }
            .eraseToAnyPublisher()
    }
}
