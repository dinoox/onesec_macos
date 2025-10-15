//
//  UDSClient.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation
import Network

enum ConnState {
    case disconnected // 未连接
    case connecting // 连接中
    case failed // 连接失败
    case connected // 已连接
    case cancelled // 取消连接
}

enum UDSClientError: Error {
    case stringConversionFailed
    case dataConversionFailed
}

protocol UDSReceiveDelegate: AnyObject {
    /// UDS 连接成功
    func didConnectToUDS()

    /// 收到快捷键设置消息
    /// - Parameters:
    ///   - mode: 识别模式 (normal/command)
    ///   - timestamp: 时间戳
    func didReceiveHotkeySetting(mode: String, timestamp: Int64)

    /// 收到快捷键设置结束消息
    /// - Parameters:
    ///   - mode: 识别模式 (normal/command)
    ///   - hotkeyCombination: 快捷键组合字符串列表
    ///   - timestamp: 时间戳
    func didReceiveHotkeySettingEnd(mode: String, hotkeyCombination: [String], timestamp: Int64)

    /// 收到初始化配置消息
    /// - Parameters:
    ///   - authToken: 认证 token
    ///   - hotkeyConfigs: 快捷键配置列表，每个配置包含 mode 与 hotkey_combination
    ///   - timestamp: 时间戳
    func didReceiveInitConfig(authToken: String?, hotkeyConfigs: [[String: Any]]?, timestamp: Int64)
}

// MARK: - UDS 客户端: Unix Domain Socket 客户端类, 用于与 Node 进程通信

final class UDSClient: @unchecked Sendable {
    private var connection: NWConnection?
    private var connectionState: ConnState = .disconnected

    private let queue = DispatchQueue(label: "uds.client.queue")
    private var messsageBuffer = Data()

    /// 连接超时时间（秒）
    private let connectionTimeoutInterval: TimeInterval = 5.0

    /// 接收消息代理
    weak var receiveDelegate: UDSReceiveDelegate?

    init() {}

    func connect() {
        let udsChannel = Config.UDS_CHANNEL

        guard connectionState != .connecting else {
            log.warning("detect connecting... return")
            return
        }

        guard FileManager.default.fileExists(atPath: udsChannel) else {
            log.warning("socket file not exist")
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        connection = NWConnection(to: NWEndpoint.unix(path: udsChannel), using: parameters)

        connection!.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            switch state {
            case .ready:
                connectionState = .connected
                startMessagePolling()
                log.debug("connected")
            case .failed: connectionState = .failed
            case .cancelled: connectionState = .cancelled
            default:
                log.debug("current connection state - \(state)")
            }
        }

        connection!.start(queue: queue)
    }

    private func startMessagePolling() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, err in
            guard let self = self else { return }
            guard err == nil else {
                log.error("reveive message err: - \(err!)")
                return
            }

            if let data = data, !data.isEmpty {
                self.messsageBuffer.append(data)
                self.processReceivedData()
            }

            if !isComplete {
                self.startMessagePolling()
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

        log.debug("reveive message type - \(typeString) \(json)")

        switch type {
        case .hotkeySetting:
            handleHotkeySettingMessage(json: json, timestamp: timestamp)
        case .hotkeySettingEnd:
            handleHotkeySettingEndMessage(json: json, timestamp: timestamp)
        case .initConfig:
            handleInitConfigMessage(json: json, timestamp: timestamp)
        default:
            log.debug("ignore message type- \(typeString)")
        }
    }

    private func handleHotkeySettingMessage(json: [String: Any], timestamp: Int64) {
        guard let data = json["data"] as? [String: Any],
              let mode = data["mode"] as? String
        else {
            log.error("UDS 客户端: 快捷键设置消息格式错误")
            return
        }

        Task { [weak self] in
            self?.receiveDelegate?.didReceiveHotkeySetting(mode: mode, timestamp: timestamp)
        }
    }

    /// 处理快捷键设置结束消息
    private func handleHotkeySettingEndMessage(json: [String: Any], timestamp: Int64) {
        guard let data = json["data"] as? [String: Any],
              let mode = data["mode"] as? String,
              let hotkeyCombination = data["hotkey_combination"] as? [String]
        else {
            log.error("UDS 客户端: 快捷键设置结束消息格式错误")
            return
        }

        Task { [weak self] in
            self?.receiveDelegate?.didReceiveHotkeySettingEnd(mode: mode, hotkeyCombination: hotkeyCombination, timestamp: timestamp)
        }
    }

    private func handleInitConfigMessage(json: [String: Any], timestamp: Int64) {
        guard let data = json["data"] as? [String: Any] else {
            log.error("UDS 客户端: 初始化配置消息格式错误")
            return
        }

        let authToken = data["auth_token"] as? String
        let hotkeyConfigs = data["hotkey_configs"] as? [[String: Any]]

        if authToken != nil {
            log.info("Init Auth Token")
        }

        if let hotkeyConfigs = hotkeyConfigs {
            for config in hotkeyConfigs {
                if let mode = config["mode"] as? String,
                   let hotkeyCombination = config["hotkey_combination"] as? [String]
                {
                    log.info("UDS 客户端: 初始化\(mode)模式快捷键 - \(hotkeyCombination)")
                }
            }
        }

        // TODO: hotkeyConfigs data race
        receiveDelegate?.didReceiveInitConfig(
            authToken: authToken,
            hotkeyConfigs: hotkeyConfigs,
            timestamp: timestamp
        )
    }
}

extension UDSClient {
    func sendStartRecording(recognitionMode: String) {
        let data: [String: Any] = [
            "recognition_mode": recognitionMode
        ]

        sendJSONMessage(WebSocketMessage.create(type: .startRecording, data: data).toJSON())
        log.debug("Send start recording: \(recognitionMode)")
    }

    func sendStopRecording() {
        sendJSONMessage(WebSocketMessage.create(type: .stopRecording).toJSON())
        log.debug("Send stop recording")
    }

    func sendModeUpgrade(fromMode: String, toMode: String, focusContext: FocusContext? = nil) {
        let data: [String: Any] = [
            "from_mode": fromMode,
            "to_mode": toMode
        ]

        // UDS 消息中不包含焦点上下文信息
        sendJSONMessage(WebSocketMessage.create(type: .modeUpgrade, data: data).toJSON())
        log.info("Send mode upgrade: \(fromMode) → \(toMode)")
    }

    func sendAuthTokenFailed(reason: String, statusCode: Int? = nil) {
        guard connectionState == .connected else {
            log.warning("Client not connected, cant send auth token failed")
            return
        }

        var data: [String: Any] = [
            "reason": reason
        ]

        if let statusCode = statusCode {
            data["status_code"] = statusCode
        }

        sendJSONMessage(WebSocketMessage.create(type: .authTokenFailed, data: data).toJSON())
        log.info("Client send auth token failed: \(reason), code: \(statusCode ?? 0)")
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
            if let error = error {
                log.error("Connection send message err: - \(error)")
            }
        })
    }
}
