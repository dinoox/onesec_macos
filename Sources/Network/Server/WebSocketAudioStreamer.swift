//
//  WebSocketAudioStreamer.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AppKit
import Foundation
import Starscream

class WebSocketAudioStreamer {
    private var ws: WebSocket?

    /// 连接状态
    var connectionState: ConnState = .disconnected

    /// 识别结果代理
    weak var messageDelegate: WebSocketMessageDelegate?

    private func createServerURL() -> URL? {
        guard let url = URL(string: Config.SERVER) else {
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

        log.info("WebSocket start connect")
    }

    func disconnect() {
        connectionState = .disconnected
        ws?.disconnect()
        ws = nil

        log.info("WebSocket disconnect")
    }

    // TODO: 发到队列
    func sendAudioData(_ audioData: Data) {
        guard connectionState == .connected, let ws = ws else {
            return
        }

        ws.write(data: audioData)
    }

    func sendMessage(_ text: String) {
        guard connectionState == .connected, let ws = ws else {
            return
        }

        ws.write(string: text)
    }

    func sendStartRecording(
        appInfo: AppInfo? = nil,
        focusContext: FocusContext? = nil,
        focusElementInfo: FocusElementInfo? = nil,
        recognitionMode: String = "normal"
    ) {
        var data: [String: Any] = ["recognition_mode": recognitionMode]

        if let appInfo = appInfo {
            data["app_info"] = appInfo.toJSON()
        }

        if let focusContext = focusContext {
            data["focus_context"] = focusContext.toJSON()
        }

        if let focusElementInfo = focusElementInfo {
            data["focus_element_info"] = focusElementInfo.toJSON()
        }

        sendWebSocketMessage(type: .startRecording)
    }

    func sendStopRecording() {
        sendWebSocketMessage(type: .stopRecording)
    }

    func sendModeUpgrade(fromMode: String, toMode: String, focusContext: FocusContext? = nil) {
        var data: [String: Any] = [
            "from_mode": fromMode,
            "to_mode": toMode
        ]

        if let focusContext = focusContext {
            data["focus_context"] = focusContext.toJSON()
        }

        sendWebSocketMessage(type: .modeUpgrade)
    }

    private func sendWebSocketMessage(type: MessageType, data: [String: Any]? = nil) {
        guard let jsonStr = WebSocketMessage.create(type: type, data: data).toJSONString() else {
            log.error("Failed to create \(type) message")
            return
        }

        log.debug("Send \(type): \(jsonStr)")
    }

    func didReceiveMessage(_ json: [String: Any]) {
        guard let summary = json["summary"] as? String else {
            return
        }

        let serverTime = json["server_time"] as? Int
        messageDelegate?.didReceiveMessage(summary, serverTime: serverTime)
    }
}
