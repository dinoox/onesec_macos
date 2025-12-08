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
    private var responseTimeoutTask: Task<Void, Never>?
    private let responseTimeoutDuration: TimeInterval = 32.0
    private var recordingStartedTimeoutTask: Task<Void, Never>?
    private let recordingStartedTimeoutDuration: TimeInterval = 3

    // 连接检测任务
    // 防止一直卡在 connecting 状态, 导致无法连接到服务器
    private var connectingCheckTask: Task<Void, Never>?

    // 空闲超时配置
    // 控制空闲时间超过 30 分钟后, 断开连接
    private var idleTimeoutTask: Task<Void, Never>?
    private let idleTimeoutDuration: TimeInterval = 30 * 60

    // 上下文发送任务
    // 确保 StopRecording 时, 上下文已经发送完毕
    private var contextTask: Task<Void, Never>?

    // 当前录音会话 ID
    private var recordingID: String = ""

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

        let serverURL = URL(string: "wss://\(Config.shared.SERVER)")!

        var request = URLRequest(url: serverURL, timeoutInterval: 60)
        request.setValue("Bearer \(Config.shared.USER_CONFIG.authToken)", forHTTPHeaderField: "Authorization")

        // 创建 Starscream WebSocket
        // 宽松的SSL配置来支持自签名证书
        ws = WebSocket(request: request, certPinner: FoundationSecurity(allowSelfSigned: true))
        ws?.delegate = self
        ws?.connect()

        scheduleConnectingCheck()

        log.info("WebSocket start connect with token \(Config.shared.USER_CONFIG.authToken) \(serverURL)")
    }

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

        let delay = min(pow(2.0, Double(curRetryCount - 1)), 30.0)

        log.info("WebSocket reconnecting in \(delay)s, reason: \(reason), attempt: \(curRetryCount)")

        Task { [weak self] in
            try? await sleep(UInt64(delay * 1000))
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
                case let .recordingStarted(mode): sendRecordingContext(); sendStartRecording(mode: mode)

                case let .recordingStopped(shouldSetResponseTimer): sendStopRecording(shouldSetResponseTimer: shouldSetResponseTimer)

                case let .modeUpgraded(from, to): sendModeUpgrade(fromMode: from, toMode: to)

                case let .audioDataReceived(data): sendAudioData(data)

                case .userDataUpdated(.auth): scheduleManualReconnect()

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
        recordingID = UUID().uuidString

        let data: [String: Any] = [
            "recognition_mode": mode.rawValue,
            "mode": Config.shared.TEXT_PROCESS_MODE.rawValue,
        ]

        sendWebSocketMessage(type: .startRecording, data: data)
        scheduleRecordingStartedTimeoutTimer()
        scheduleIdleTimer()
    }

    func sendStopRecording(shouldSetResponseTimer: Bool = true) {
        Task { [weak self] in
            await self?.contextTask?.value
            self?.sendWebSocketMessage(type: .stopRecording)
            if shouldSetResponseTimer {
                self?.startResponseTimeoutTimer()
            }
        }
    }

    func sendModeUpgrade(fromMode: RecordMode, toMode: RecordMode) {
        let data: [String: Any] = [
            "from_mode": fromMode.rawValue,
            "to_mode": toMode.rawValue,
        ]

        sendWebSocketMessage(type: .modeUpgrade, data: data)
    }

    func sendRecordingContext() {
        contextTask = Task {
            let appInfo = ContextService.getAppInfo()
            let hostInfo = ContextService.getHostInfo()
            let selectText = await ContextService.getSelectedText()
            let inputContent = ContextService.getInputContent()

            let historyContentStart = CFAbsoluteTimeGetCurrent()
            let historyContent = ContextService.getHistoryContent()
            let historyContentDuration = (CFAbsoluteTimeGetCurrent() - historyContentStart) * 1000
            log.debug("⏱️ 获取历史内容: \(String(format: "%.2f", historyContentDuration))ms")

            let focusContext = FocusContext(inputContent: inputContent ?? "", selectedText: selectText ?? "", historyContent: historyContent ?? "")
            let focusElementInfo = ContextService.getFocusElementInfo()

            let appContext = AppContext(
                appInfo: appInfo,
                hostInfo: hostInfo,
                focusContext: focusContext,
                focusElementInfo: focusElementInfo
            )

            sendWebSocketMessage(type: .contextUpdated, data: appContext.toJSON())
            EventBus.shared.publish(.recordingContextUpdated(context: appContext))
        }
    }

    func handleServerResourceRequested(type: String) {
        var data: [String: Any] = [
            "resource_type": type,
        ]

        if type == "screenshot" {
            guard let screenshot = OCRService.captureFrontWindow() else {
                return
            }
            // 将 CGImage 转换为 JPEG 格式并压缩
            let bitmapRep = NSBitmapImageRep(cgImage: screenshot)
            guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else {
                log.error("cant compress screenshot")
                return
            }
            data["image"] = jpegData.base64EncodedString()
        }

        if type == "full_context" {
            data["text"] = ContextService.getInputContent(contextLength: 0) ?? ""
        }

        sendWebSocketMessage(type: .resourceRequested, data: data)
    }

    private func sendWebSocketMessage(type: MessageType, data: [String: Any]? = nil) {
        guard let jsonStr = WebSocketMessage.create(id: recordingID, type: type, data: data).toJSONString() else {
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

        case .error:
            cancelRecordingStartedTimeoutTimer()
            guard let message = json["message"] as? String else { return }
            EventBus.shared.publish(.notificationReceived(.error(title: "错误", content: message)))

        case .resourceRequested:
            guard let data = json["data"] as? [String: Any],
                  let type = data["resource_type"] as? String else { return }
            handleServerResourceRequested(type: type)

        case .recognitionSummary:
            cancelResponseTimeoutTimer()
            guard let data = json["data"] as? [String: Any],
                  let summary = data["summary"] as? String,
                  let interactionID = data["interaction_id"] as? String,
                  let processMode = data["process_mode"] as? String
            else {
                return
            }

            var polishedText: String?
            if processMode == "TRANSLATE" {
                let translateRes = data["translate_result"] as? [String: Any]
                let text = translateRes?["polished_text"] as? String

                polishedText = text ?? ""
            }

            EventBus.shared.publish(.serverResultReceived(summary: summary, interactionID: interactionID, processMode: TextProcessMode(rawValue: processMode) ?? .auto, polishedText: polishedText ?? ""))

        case .terminalLinuxChoice:
            cancelResponseTimeoutTimer()
            guard let data = json["data"] as? [String: Any],
                  let commands = data["commands"] as? [[String: Any]]
            else {
                return
            }

            let bundleID = data["bundle_id"] as? String ?? ""
            let appName = data["app_name"] as? String ?? ""
            let endpointIdentifier = data["endpoint_identifier"] as? String ?? ""

            let linuxCommands = commands.compactMap {
                LinuxCommand(distro: $0["distro"] as? String ?? "",
                             command: $0["command"] as? String ?? "",
                             displayName: $0["display_name"] as? String ?? "")
            }
            EventBus.shared.publish(.terminalLinuxChoice(bundleID: bundleID, appName: appName, endpointIdentifier: endpointIdentifier, commands: linuxCommands))

        default:
            break
        }
    }
}

// MARK: - 定时器

extension WebSocketAudioStreamer {
    private func startResponseTimeoutTimer() {
        cancelResponseTimeoutTimer()

        responseTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await sleep(UInt64(responseTimeoutDuration * 1000))
            guard !Task.isCancelled else { return }
            log.warning("Recording response timed out after \(responseTimeoutDuration) seconds")
            EventBus.shared.publish(.notificationReceived(.serverTimeout))
        }
        log.debug("Started response timeout timer (\(responseTimeoutDuration)s)")
    }

    private func cancelResponseTimeoutTimer() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
    }

    private func scheduleRecordingStartedTimeoutTimer() {
        cancelRecordingStartedTimeoutTimer()

        recordingStartedTimeoutTask = Task { [weak self] in
            guard let self else { return }
            try? await sleep(UInt64(recordingStartedTimeoutDuration * 1000))
            guard !Task.isCancelled else { return }
            log.warning("Recording started response timed out after \(recordingStartedTimeoutDuration) seconds")
            EventBus.shared.publish(.notificationReceived(.serverUnavailable(duringRecording: true)))
            cancelResponseTimeoutTimer()
        }
        log.debug("Started recording started timeout timer (\(recordingStartedTimeoutDuration)s)")
    }

    private func cancelRecordingStartedTimeoutTimer() {
        recordingStartedTimeoutTask?.cancel()
        recordingStartedTimeoutTask = nil
    }

    private func scheduleConnectingCheck() {
        connectingCheckTask?.cancel()
        connectingCheckTask = nil

        connectingCheckTask = Task { [weak self] in
            guard let self else { return }
            try? await sleep(10000) // 10秒
            guard !Task.isCancelled else { return }
            if connectionState == .connecting {
                log.warning("Still connecting after 10s, reconnect")
                scheduleManualReconnect()
            }
        }
    }

    private func scheduleIdleTimer() {
        idleTimeoutTask?.cancel()

        idleTimeoutTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await sleep(UInt64(idleTimeoutDuration * 1000))
                log.warning("No recording activity for \(idleTimeoutDuration / 60) minutes, disconnecting")
                connectionState = .manualDisconnected
                ws?.disconnect()
                ws = nil
            } catch {
                // Task Canceled
            }
        }
    }
}
