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

class WebSocketAudioStreamer: @unchecked Sendable {
    private var ws: WebSocket?

    private var cancellables = Set<AnyCancellable>()

    @Published var connectionState: ConnState = .manualDisconnected

    // Reconnect 配置
    var curRetryCount = 0
    let maxRetryCount = 10

    // Server 超时配置
    private var responseTimeoutTimer: DispatchWorkItem?
    private let responseTimeoutDuration: TimeInterval = 10.0
    private var recordingStartedTimeoutTimer: DispatchWorkItem?
    private let recordingStartedTimeoutDuration: TimeInterval = 2

    // 连接检测 (防止一直卡在 connecting)
    private var connectingCheckTimer: DispatchWorkItem?

    // 空闲超时配置 (30分钟没有使用就断开)
    var idleTimeoutTimer: DispatchWorkItem?
    let idleTimeoutDuration: TimeInterval = 30 * 60

    init() {
        initializeMessageListener()
    }

    func connect() {
        guard ConnectionCenter.shared.isAuthed else {
            log.info("no auth, skip connect")
            connectionState = .manualDisconnected
            return
        }

        guard connectionState != .connecting, connectionState != .connected else {
            log.info("WebSocket already \(connectionState)")
            return
        }

        if ws != nil {
            ws?.disconnect()
            ws = nil
        }
        connectionState = .connecting

        let serverURL = URL(string: "wss://\(Config.SERVER)")!

        var request = URLRequest(url: serverURL, timeoutInterval: 60)
        request.setValue("Bearer \(Config.AUTH_TOKEN)", forHTTPHeaderField: "Authorization")

        // 创建 Starscream WebSocket
        // 使用更宽松的SSL配置来支持自签名证书
        ws = WebSocket(request: request, certPinner: FoundationSecurity(allowSelfSigned: true))
        ws?.delegate = self
        ws?.connect()

        scheduleConnectingCheck()

        log.info("WebSocket start connect with token \(Config.AUTH_TOKEN) \(serverURL)")
    }

    /// 重新连接触发时机为
    /// - 连接错误（error）
    /// - 服务器建议重连（reconnectSuggested）
    /// - 对端关闭连接（peerClosed）
    /// - 用户配置变更 (userConfigChanged)
    func scheduleReconnect(reason: String) {
        guard ConnectionCenter.shared.isAuthed else {
            log.warning("Auth Token invaild, stop reconnect")
            return
        }
        guard connectionState != .connecting else {
            log.warning("Already connecting, skip reconnect")
            return
        }

        curRetryCount += 1

        guard curRetryCount <= maxRetryCount else {
            log.error("The server is unavailable, stopping reconnection.")
            return
        }

        // 指数退避策略：1s, 2s, 4s, 8s, 16s，最多 30s
        let delay = min(pow(2.0, Double(curRetryCount - 1)), 30.0)

        log.info(
            "WebSocket reconnecting in \(delay)s, reason: \(reason), attempt: \(curRetryCount)")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    private func scheduleManualReconnect() {
        disconnect()
        connect()
    }

    private func disconnect() {
        connectionState = .manualDisconnected
        ws?.disconnect()
        ws = nil
    }
}

// MARK: - 消息处理

extension WebSocketAudioStreamer {
    func initializeMessageListener() {
        EventBus.shared.events
            .sink { [weak self] event in
                guard let self else { return }

                switch event {
                case .recordingStarted(let mode): sendStartRecording(mode: mode)

                case .recordingStopped: sendStopRecording()

                case .modeUpgraded(let from, let to): sendModeUpgrade(fromMode: from, toMode: to)

                case .audioDataReceived(let data): sendAudioData(data)

                case .userConfigUpdated: scheduleManualReconnect()

                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

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
        mode: RecordMode = .normal,
    ) {
        let data: [String: Any] = [
            "recognition_mode": mode.rawValue,
            "mode": Config.TEXT_PROCESS_MODE.rawValue,
        ]

        sendWebSocketMessage(type: .startRecording, data: data)
        Task {
            let appInfo = ContextService.getAppInfo()
            let selectText = await ContextService.getSelectedText()
            let inputContent = ContextService.getInputContent()

            let focusContext = FocusContext(inputContent: inputContent ?? "", selectedText: selectText ?? "")
            let focusElementInfo = ContextService.getFocusElementInfo()
            sendRecordingContext(appInfo: appInfo, focusContext: focusContext, focusElementInfo: focusElementInfo)
        }
        scheduleRecordingStartedTimeoutTimer()
        scheduleIdleTimer()
    }

    func sendStopRecording() {
        sendWebSocketMessage(type: .stopRecording)
        startResponseTimeoutTimer()
    }

    func sendModeUpgrade(fromMode: RecordMode, toMode: RecordMode) {
        let data: [String: Any] = [
            "from_mode": fromMode.rawValue,
            "to_mode": toMode.rawValue,
        ]

        sendWebSocketMessage(type: .modeUpgrade, data: data)
    }

    func sendRecordingContext(
        appInfo: AppInfo,
        focusContext: FocusContext,
        focusElementInfo: FocusElementInfo,
    ) {
        let data: [String: Any] = [
            "app_info": appInfo.toJSON(),
            "focus_context": focusContext.toJSON(),
            "focus_element_info": focusElementInfo.toJSON(),
        ]

        sendWebSocketMessage(type: .contextUpdated, data: data)
    }

    private func sendWebSocketMessage(type: MessageType, data: [String: Any]? = nil) {
        guard let jsonStr = WebSocketMessage.create(type: type, data: data).toJSONString() else {
            log.error("Failed to create \(type) message")
            return
        }

        log.debug("Send to server: \(jsonStr)")
        sendMessage(jsonStr)
    }

    func didReceiveMessage(_ json: [String: Any]) {
        guard let typeStr = json["type"] as? String,
              let messageType = MessageType(rawValue: typeStr)
        else { return }

        switch messageType {
        case .recordingStarted:
            cancelRecordingStartedTimeoutTimer()

        case .recognitionSummary:
            cancelResponseTimeoutTimer()
            guard let data = json["data"] as? [String: Any],
                  let summary = data["summary"] as? String
            else { return }
            let serverTime = data["server_time"] as? Int
            EventBus.shared.publish(.serverResultReceived(summary: summary, serverTime: serverTime))

        default:
            break
        }
    }

    private func startResponseTimeoutTimer() {
        cancelResponseTimeoutTimer()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            log.warning("Recording response timed out after \(responseTimeoutDuration) seconds")
            EventBus.shared.publish(.notificationReceived(.serverTimeout))
        }

        responseTimeoutTimer = workItem
        DispatchQueue.global().asyncAfter(
            deadline: .now() + responseTimeoutDuration, execute: workItem)
        log.debug("Started response timeout timer (\(responseTimeoutDuration)s)")
    }

    private func cancelResponseTimeoutTimer() {
        responseTimeoutTimer?.cancel()
        responseTimeoutTimer = nil
    }

    private func scheduleRecordingStartedTimeoutTimer() {
        cancelRecordingStartedTimeoutTimer()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            log.warning(
                "Recording started response timed out after \(recordingStartedTimeoutDuration) seconds")
            EventBus.shared.publish(.notificationReceived(.recordingTimeout))
        }

        recordingStartedTimeoutTimer = workItem
        DispatchQueue.global().asyncAfter(
            deadline: .now() + recordingStartedTimeoutDuration, execute: workItem)
        log.debug("Started recording started timeout timer (\(recordingStartedTimeoutDuration)s)")
    }

    private func cancelRecordingStartedTimeoutTimer() {
        recordingStartedTimeoutTimer?.cancel()
        recordingStartedTimeoutTimer = nil
    }

    private func scheduleConnectingCheck() {
        connectingCheckTimer?.cancel()
        connectingCheckTimer = nil

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if connectionState == .connecting {
                log.warning("Still connecting after 10s, reconnect")
                scheduleManualReconnect()
            }
        }

        connectingCheckTimer = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0, execute: workItem)
    }

    private func scheduleIdleTimer() {
        idleTimeoutTimer?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            log.warning("No recording activity for \(idleTimeoutDuration / 60) minutes, disconnecting")
            connectionState = .manualDisconnected
            ws?.disconnect()
            ws = nil
        }

        idleTimeoutTimer = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + idleTimeoutDuration, execute: workItem)
    }
}
