//
//  EventBus.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import Combine
import Foundation

enum AppEvent {
    case volumeChange(volume: Float)
    case onAudioData(data: Data)
    case startRecording(appInfo: AppInfo?, focusContext: FocusContext?, focusElementInfo: FocusElementInfo?, recordMode: RecordMode)
    case stopRecording
    case serverResult(summary: String, serverTime: Int?)
    case modeUpgrade(fromMode: RecordMode, toMode: RecordMode, focusContext: FocusContext?)
    case authTokenFailed(reason: String, statusCode: Int?)
    case notification(title: String, content: String)
}

class EventBus: @unchecked Sendable {
    static let shared = EventBus()
    let eventSubject = PassthroughSubject<AppEvent, Never>()

    // 发布事件
    func publish(_ event: AppEvent) {
        eventSubject.send(event)
    }

    // 订阅所有事件
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
                guard case .volumeChange(let volume) = event else { return nil }
                return volume
            }
            .eraseToAnyPublisher()
    }

    var serverResult: AnyPublisher<String, Never> {
        eventSubject
            .compactMap { event in
                guard case .serverResult(let summary, let serverTime) = event else { return nil }
                return summary
            }
            .eraseToAnyPublisher()
    }
}
