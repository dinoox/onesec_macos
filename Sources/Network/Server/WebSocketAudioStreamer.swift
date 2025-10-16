//
//  WebSocketAudioStreamer.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AppKit
import Combine
import Foundation
import Starscream

class WebSocketAudioStreamer {
    private var ws: WebSocket?

    private var cancellables = Set<AnyCancellable>()

    var connectionState: ConnState = .disconnected

    init() {
        EventBus.shared.events
            .sink { [weak self] event in
                guard let self else { return }

                switch event {
                case .recordingStarted(let appInfo, let focusContext, let focusElementInfo, let recordMode):
                    sendStartRecording(
                        appInfo: appInfo,
                        focusContext: focusContext,
                        focusElementInfo: focusElementInfo,
                        recordMode: recordMode
                    )

                case .recordingStopped:
                    sendStopRecording()

                case .modeUpgraded(let fromMode, let toMode, let focusContext):
                    sendModeUpgrade(fromMode: fromMode, toMode: toMode, focusContext: focusContext)

                case .audioDataReceived(let data): sendAudioData(data)

                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func createServerURL() -> URL? {
        guard let url = URL(string: "wss://\(Config.SERVER)") else {
            log.error("Create webSocket server URL failed")
            return nil
        }
        return url
    }

    func connect() {
        disconnect()

        guard let serverURL = createServerURL() else {
            return
        }

        var request = URLRequest(url: serverURL)
        request.timeoutInterval = 60
        request.setValue("Bearer \(Config.AUTH_TOKEN)", forHTTPHeaderField: "Authorization")

        // 创建 Starscream WebSocket
        // 使用更宽松的SSL配置来支持自签名证书
        let pinner = FoundationSecurity(allowSelfSigned: true)
        ws = WebSocket(request: request, certPinner: pinner)
        ws?.delegate = self
        ws?.connect()

        log.info("WebSocket start connect with token \(Config.AUTH_TOKEN) \(serverURL)")
    }

    func disconnect() {
        connectionState = .disconnected
        ws?.disconnect()
        ws = nil

        log.info("WebSocket disconnect")
    }

    // TODO: 发到队列
    func sendAudioData(_ audioData: Data) {
        guard connectionState == .connected, let ws else {
            return
        }
        
        ws.write(data: audioData)
    }

    func sendMessage(_ text: String) {
        guard connectionState == .connected, let ws else {
            return
        }

        ws.write(string: text)
    }

    func sendStartRecording(
        appInfo: AppInfo? = nil,
        focusContext: FocusContext? = nil,
        focusElementInfo: FocusElementInfo? = nil,
        recordMode: RecordMode = .normal
    ) {
        var data: [String: Any] = ["recognition_mode": recordMode.rawValue]

        if let appInfo {
            data["app_info"] = appInfo.toJSON()
        }

        if let focusContext {
            data["focus_context"] = focusContext.toJSON()
        }

        if let focusElementInfo {
            data["focus_element_info"] = focusElementInfo.toJSON()
        }

        sendWebSocketMessage(type: .startRecording, data: data)
    }

    func sendStopRecording() {
        sendWebSocketMessage(type: .stopRecording)
    }

    func sendModeUpgrade(fromMode: RecordMode, toMode: RecordMode, focusContext: FocusContext? = nil) {
        var data: [String: Any] = [
            "from_mode": fromMode.rawValue,
            "to_mode": toMode.rawValue
        ]

        if let focusContext {
            data["focus_context"] = focusContext.toJSON()
        }

        sendWebSocketMessage(type: .modeUpgrade, data: data)
    }

    private func sendWebSocketMessage(type: MessageType, data: [String: Any]? = nil) {
        guard let jsonStr = WebSocketMessage.create(type: type, data: data).toJSONString() else {
            log.error("Failed to create \(type) message")
            return
        }

        log.debug("Send to server \(type): \(jsonStr)")
        sendMessage(jsonStr)
    }

    func didReceiveMessage(_ json: [String: Any]) {
        guard let data = json["data"] as? [String: Any] else {
            return
        }

        guard let summary = data["summary"] as? String else {
            return
        }

        let serverTime = data["server_time"] as? Int
        EventBus.shared.publish(.serverResultReceived(summary: summary, serverTime: serverTime))
    }
}
