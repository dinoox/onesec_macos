//
//  EventBus.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import Combine
import Foundation

enum AppEvent {
    case volumeChanged(volume: Float)
    case recordingStarted(appInfo: AppInfo?, focusContext: FocusContext?, focusElementInfo: FocusElementInfo?, recordMode: RecordMode)
    case recordingStopped
    case audioDataReceived(data: Data)
    case serverResultReceived(summary: String, serverTime: Int?)
    case modeUpgraded(fromMode: RecordMode, toMode: RecordMode, focusContext: FocusContext?)
    case authTokenFailed(reason: String, statusCode: Int?)
    case notificationReceived(title: String, content: String)
}

class EventBus: @unchecked Sendable {
    static let shared = EventBus()
    let eventSubject = PassthroughSubject<AppEvent, Never>()

    // 发布事件
    func publish(_ event: AppEvent) {
        eventSubject.send(event)
    }

    // 订阅所有
    var events: AnyPublisher<AppEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    func subscribe<T>(to eventType: T.Type) -> AnyPublisher<T, Never> {
        eventSubject
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
    var volumeChange: AnyPublisher<Float, Never> {
        eventSubject
            .compactMap { event in
                guard case .volumeChanged(let volume) = event else { return nil }
                return volume
            }
            .eraseToAnyPublisher()
    }
}
