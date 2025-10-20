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
    case disconnected
    case connecting
    case failed
    case connected
    case cancelled
}

enum UDSClientError: Error {
    case stringConversionFailed
    case dataConversionFailed
}

// MARK: - Unix Domain Socket 客户端, 负责与 Node 进程通信

final class UDSClient: @unchecked Sendable {
    private var connection: NWConnection?
    @Published  var connectionState: ConnState = .disconnected

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
                case let .authTokenFailed(reason, statusCode):
                    self?.sendAuthTokenFailed(reason: reason, statusCode: statusCode)

                case let .hotkeySettingEnded(mode, hotkeyCombination):
                    self?.sendHotkeySettingResult(mode: mode, hotkeyCombination: hotkeyCombination)

                case let .hotkeySettingUpdated(mode, hotkeyCombination):
                    self?.sendHotkeySettingUpdate(mode: mode, hotkeyCombination: hotkeyCombination)

                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    func connect(isRetry: Bool = false) {
        let udsChannel = Config.UDS_CHANNEL

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
        case .hotkeySetting:
            handleHotkeySettingMessage(json: json, timestamp: timestamp)
        case .hotkeySettingEnd:
            handleHotkeySettingEndMessage(json: json, timestamp: timestamp)
        case .initConfig:
            handleInitConfigMessage(json: json, timestamp: timestamp)
        default:
            break
        }
    }

    private func handleHotkeySettingMessage(json: [String: Any], timestamp: Int64) {
        guard let data = json["data"] as? [String: Any],
              let mode = data["mode"] as? String
        else {
            log.error("UDS 客户端: 快捷键设置消息格式错误")
            return
        }

        EventBus.shared.publish(.hotkeySettingStarted(mode: mode == "normal" ? .normal : .command))
    }

    private func handleHotkeySettingEndMessage(json: [String: Any], timestamp: Int64) {
        guard let data = json["data"] as? [String: Any],
              let mode = data["mode"] as? String,
              let hotkeyCombination = data["hotkey_combination"] as? [String]
        else {
            log.error("UDS 客户端: 快捷键设置结束消息格式错误")
            return
        }

        EventBus.shared.publish(.hotkeySettingEnded(mode: mode == "normal" ? .normal : .command, hotkeyCombination: hotkeyCombination))
    }

    private func handleInitConfigMessage(json: [String: Any], timestamp: Int64) {
        guard
            let data = json["data"] as? [String: Any],
            let authToken = data["auth_token"] as? String,
            let hotkeyConfigs = data["hotkey_configs"] as? [[String: Any]]
        else {
            return
        }

        EventBus.shared.publish(.userConfigChanged(authToken: authToken, hotkeyConfigs: hotkeyConfigs))
    }

    func sendAuthTokenFailed(reason: String, statusCode: Int? = nil) {
        guard connectionState == .connected else {
            log.warning("Client not connected, cant send auth token failed")
            return
        }

        var data: [String: Any] = [
            "reason": reason
        ]

        if let statusCode {
            data["status_code"] = statusCode
        }

        sendJSONMessage(WebSocketMessage.create(type: .authTokenFailed, data: data).toJSON())
        log.info("Client send auth token failed: \(reason), code: \(statusCode ?? 0)")
    }

    func sendHotkeySettingUpdate(mode: RecordMode, hotkeyCombination: [String]) {
        guard connectionState == .connected else {
            log.warning("Client not connected, cant send hotkey setting update")
            return
        }

        let data: [String: Any] = [
            "mode": mode.rawValue,
            "hotkey_combination": hotkeyCombination
        ]

        sendJSONMessage(WebSocketMessage.create(type: .hotkeySettingUpdate, data: data).toJSON())
        log.debug("Client send hotkey setting update: mode=\(mode), combination=\(hotkeyCombination)")
    }

    func sendHotkeySettingResult(mode: RecordMode, hotkeyCombination: [String]) {
        guard connectionState == .connected else {
            log.warning("Client not connected, cant send hotkey setting result")
            return
        }

        let data: [String: Any] = [
            "mode": mode.rawValue,
            "hotkey_combination": hotkeyCombination
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
