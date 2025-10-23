//
//  protocol.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AppKit
import Foundation
import Starscream

extension WebSocketAudioStreamer: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            log.debug("WebSocket connected")
            connectionState = .connected
            curRetryCount = 0

        case .disconnected(let reason, let code):
            log.debug("WebSocket disconnect with: \(reason) code: \(code)")
            connectionState = .disconnected
            // 正常断开连接时触发重连
            scheduleReconnect(reason: "Disconnected: \(reason)")

        case .text(let string):
            log.debug("WebSocket receive text: \(string)")

            guard let data = string.data(using: .utf8) else {
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.error("WebSocket JSON parse failed")
                return
            }

            didReceiveMessage(json)

        case .binary(let data):
            log.debug("WebSocket receive binary: \(data.count) 字节")

        case .ping:
            log.debug("WebSocket receive ping")

        case .pong:
            log.debug("WebSocket receive pong")

        case .viabilityChanged(let isViable):
            log.debug("WebSocket viabilityChanged: \(isViable)")

        case .reconnectSuggested(let shouldReconnect):
            log.warning("Websocket recommand reconnect: \(shouldReconnect)")
            if shouldReconnect {
                scheduleReconnect(reason: "Server suggested reconnect")
            }

        case .cancelled:
            log.warning("WebSocket connection canceled")
            connectionState = .cancelled

        case .error(let error):
            log.error("WebSocket connection err: \(error?.localizedDescription ?? "Unknown error")")
            connectionState = .failed

            // 1) 兼容 Starscream 抛出的 HTTP 升级错误：HTTPUpgradeError
            if let upgrade = error as? HTTPUpgradeError {
                switch upgrade {
                case .notAnUpgrade(let statusCode, _ /* headers */):
                    handleHTTPUpgradeFailure(status: statusCode, message: "notAnUpgrade")
                    return
                case .invalidData:
                    // 协议/数据无效，按常规断线处理
                    scheduleReconnect(reason: "Invalid protocol data")
                    break
                @unknown default:
                    scheduleReconnect(reason: "Unknown HTTP upgrade error")
                }
            } else {
                // 其他错误，触发重连
                scheduleReconnect(
                    reason: "Connection error: \(error?.localizedDescription ?? "Unknown")")
            }

        case .peerClosed:
            log.info("websocket peer closed")
            guard connectionState != .connecting else {
                return
            }

            connectionState = .disconnected
            scheduleReconnect(reason: "Peer closed connection")
        }
    }

    /// 处理握手阶段的 HTTP 升级失败（常见于 401/403）
    func handleHTTPUpgradeFailure(status: Int, message: String) {
        log.error("WebSocket handshake failed with: \(status)，message: \(message)")
        connectionState = .disconnected

        guard ![401, 403].contains(status) else {
            curRetryCount = 0
            let reason = status == 401 ? "auth invalid" : "permission denied"
            log.warning("WebSocket auth failed (\(status)), \(reason) stop auto-reconnect")
            EventBus.shared.publish(.notificationReceived(.authTokenFailed))
            return
        }

        scheduleReconnect(reason: "HTTP upgrade failed: \(status)")
    }
}
