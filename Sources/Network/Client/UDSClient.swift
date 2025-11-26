//
//  UDSClient.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Combine
import Foundation
import Network

enum ConnState {
    case preparing
    case disconnected
    case connecting
    case failed
    case connected
    case cancelled
    case manualDisconnected // 手动断开
}

enum UDSClientError: Error {
    case stringConversionFailed
    case dataConversionFailed
}

// MARK: - Unix Domain Socket 客户端, 负责与 Node 进程通信

final class UDSClient: @unchecked Sendable {
    private var connection: NWConnection?
    @Published var connectionState: ConnState = .disconnected

    private let queue = DispatchQueue(label: "uds.client.queue")
    private var messsageBuffer = Data()

    /// Reconnect 配置
    private var maxRetryCount = 10
    private var curRetryCount = 0

    private var cancellables = Set<AnyCancellable>()

    init() {
        EventBus.shared.events
            .sink { [weak self] event in
                switch event {
                case .notificationReceived(.authTokenFailed): self?.sendAuthTokenFailed()
                case let .hotkeySettingEnded(mode, hotkeyCombination):
                    self?.sendHotkeySettingResult(mode: mode, hotkeyCombination: hotkeyCombination)
                case let .hotkeySettingResulted(mode, hotkeyCombination, isConflict):
                    if !isConflict {
                        self?.sendHotkeySettingResult(mode: mode, hotkeyCombination: hotkeyCombination)
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func connect(isRetry: Bool = false) {
        let udsChannel = Config.shared.UDS_CHANNEL

        guard connectionState != .connecting else {
            log.warning("detect connecting... return")
            return
        }

        guard FileManager.default.fileExists(atPath: udsChannel) else {
            log.warning("socket file not exist")
            if isRetry, curRetryCount < maxRetryCount {
                scheduleReconnect(reason: "socket文件不存在")
            }
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        connection = NWConnection(to: NWEndpoint.unix(path: udsChannel), using: parameters)

        connection!.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                connectionState = .connected
                startMessagePolling()
                log.info("connected")
            case .failed:
                connectionState = .failed
                log.info("connect failed")
                scheduleReconnect(reason: "连接失败")
            case .cancelled: connectionState = .cancelled
            case .preparing: connectionState = .preparing
            default:
                log.debug("current connection state - \(state)")
            }
        }

        connection!.start(queue: queue)
    }

    private func scheduleReconnect(reason: String) {
        curRetryCount += 1

        guard curRetryCount <= maxRetryCount else {
            log.error("The server is unavailable, stopping reconnection.")
            return
        }

        // 更快的重连：0.5s, 1s, 2s, 4s, 最多 5s
        let delay = min(0.5 * pow(2.0, Double(curRetryCount - 1)), 5.0)

        log.info("Reconnecting in \(delay) seconds \(reason), attempt \(curRetryCount)")

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect(isRetry: true)
        }
    }
}

// MARK: - 消息处理

extension UDSClient {
    private func startMessagePolling() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, err in
            guard let self else { return }
            guard err == nil else {
                log.error("reveive message err: - \(err!)")
                return
            }

            if let data, !data.isEmpty {
                messsageBuffer.append(data)
                processReceivedData()
            }

            if !isComplete {
                startMessagePolling()
            }
        }
    }

    private func processReceivedData() {
        let dataString = String(data: messsageBuffer, encoding: .utf8) ?? ""
        let lines = dataString.components(separatedBy: "\n")

        // 处理完整的消息行
        for i in 0 ..< lines.count - 1 {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                processMessage(line)
            }
        }

        // 保留最后一行（可能不完整）
        if let lastLine = lines.last, !lastLine.isEmpty {
            messsageBuffer = lastLine.data(using: .utf8) ?? Data()
        } else {
            messsageBuffer = Data()
        }
    }

    private func processMessage(_ message: String) {
        log.debug("Reveive message \(message)")
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let typeString = json["type"] as? String,
              let timestamp = json["timestamp"] as? Int64,
              let type = MessageType(rawValue: typeString)
        else {
            log.debug("cannot parse message - \(message)")
            return
        }

        log.debug("Reveive message \(json)")

        switch type {
        case .configUpdated:
            handleConfigUpdatedMessage(json: json, timestamp: timestamp)
        case .authTokenFailed:
            handleAuthTokenFailed()
        default:
            break
        }
    }

    private func handleConfigUpdatedMessage(json _: [String: Any], timestamp _: Int64) {
        let token = Config.shared.USER_CONFIG.authToken
        Config.shared.USER_CONFIG = UserConfigService.shared.loadUserConfig()

        if token != Config.shared.USER_CONFIG.authToken {
            ConnectionCenter.shared.isAuthed = JWTValidator.isValid(Config.shared.USER_CONFIG.authToken)
            log.info("ConnectionCenter.shared.isAuthed \(ConnectionCenter.shared.isAuthed)")
            EventBus.shared.publish(.userDataUpdated(.auth))
            return
        }

        EventBus.shared.publish(.userDataUpdated(.config))
    }

    func handleAuthTokenFailed() {
        // ConnectionCenter.shared.cleanInputService()
        ConnectionCenter.shared.isAuthed = false
    }

    func sendAuthTokenFailed(reason: String = "UnAuth", statusCode: Int? = nil) {
        guard connectionState == .connected else {
            log.warning("Client not connected, cant send auth token failed")
            return
        }

        var data: [String: Any] = [
            "reason": reason,
        ]

        if let statusCode {
            data["status_code"] = statusCode
        }

        sendJSONMessage(WebSocketMessage.create(type: .authTokenFailed, data: data).toJSON())
        log.info("Client send auth token failed: \(reason), code: \(statusCode ?? 0)")
    }

    func sendHotkeySettingResult(mode: RecordMode, hotkeyCombination: [String]) {
        guard connectionState == .connected else {
            log.warning("Client not connected, cant send hotkey setting result")
            return
        }

        let data: [String: Any] = [
            "mode": mode.rawValue,
            "hotkey_combination": hotkeyCombination,
        ]

        sendJSONMessage(WebSocketMessage.create(type: .hotkeySettingResult, data: data).toJSON())
        log.info("Client send hotkey setting result: mode=\(mode), combination=\(hotkeyCombination)")
    }

    func sendJSONMessage(_ message: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: [])
            try sendData(jsonData)
        } catch {
            log.error("Client json serialize failed - \(error)")
        }
    }

    func sendData(_ jsonData: Data) throws {
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw UDSClientError.stringConversionFailed
        }

        guard let data = (jsonString + "\n").data(using: .utf8) else {
            throw UDSClientError.dataConversionFailed
        }

        connection!.send(content: data, completion: .contentProcessed { error in
            if let error {
                log.error("Connection send message err: - \(error)")
            }
        })
    }
}
