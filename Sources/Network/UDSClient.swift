//
//  UDSClient.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation
import Network

enum UDSConnState {
    case disconnected // 未连接
    case connecting // 连接中
    case failed // 连接失败
    case connected // 已连接
    case cancelled // 取消连接
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
    private var connectionState: UDSConnState = .disconnected

    private let queue = DispatchQueue(label: "uds.client.queue")
    private var messsageBuffer = Data()

    /// 连接超时时间（秒）
    private let connectionTimeoutInterval: TimeInterval = 5.0

    /// 接收消息代理
    weak var receiveDelegate: UDSReceiveDelegate?

    init() {}

    func connect() {
        let udsChannel = Config.UDS_CHANNEL

        guard connectionState == .connecting else {
            log.warning("UDSClient: 正在连接中，跳过重复连接")
            return
        }

        guard FileManager.default.fileExists(atPath: udsChannel) else {
            log.warning("UDSClient Socket 文件不存在")
            return
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        connection = NWConnection(to: NWEndpoint.unix(path: udsChannel), using: parameters)

        connection!.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }

            log.debug("UDSClient: 当前连接状态 - \(state)")
            switch state {
            case .ready:
                connectionState = .connected
                startMessagePolling()
            case .failed: connectionState = .failed
            case .cancelled: connectionState = .cancelled
            default:
                log.warning("UDSClient: 当前连接状态 - \(state)")
            }
        }

        connection!.start(queue: queue)
    }

    private func startMessagePolling() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, err in
            guard let self = self else { return }
            guard err == nil else {
                log.error("UDSClient: 接收消息失败 - \(err!)")
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
            log.debug("UDSClient: 无法解析消息 - \(message)")
            return
        }

        log.debug("UDSClient: 收到消息类型 - \(typeString)")

        switch type {
        case .hotkeySetting:
            handleHotkeySettingMessage(json: json, timestamp: timestamp)
        case .hotkeySettingEnd:
            handleHotkeySettingEndMessage(json: json, timestamp: timestamp)
        case .initConfig:
            handleInitConfigMessage(json: json, timestamp: timestamp)
        default:
            log.debug("UDS 客户端: 忽略消息类型 - \(typeString)")
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
            log.info("UDS 客户端: 初始化 Auth Token")
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
