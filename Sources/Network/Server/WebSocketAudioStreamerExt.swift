//
//  WebSocketAudioStreamerExt.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AppKit
import Foundation
import Starscream

extension WebSocketAudioStreamer: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client _: WebSocketClient) {
        switch event {
        case .connected:
            log.debug("WebSocket connected")
            connectionState = .connected
            curRetryCount = 0

        case let .disconnected(reason, code):
            log.debug("WebSocket disconnect with: \(reason) code: \(code)")
            connectionState = .disconnected
            // 正常断开连接时触发重连
            scheduleReconnect(reason: "Disconnected: \(reason)")

        case let .text(string):
            log.debug("WebSocket receive text: \(string)")

            guard let data = string.data(using: .utf8) else {
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.error("WebSocket JSON parse failed")
                return
            }

            didReceiveMessage(json)

        case let .binary(data):
            log.debug("WebSocket receive binary: \(data.count)")

        case .ping:
            ping()

        case .pong:
            updateLastPongTime()

        case let .viabilityChanged(isViable):
            log.debug("WebSocket viabilityChanged: \(isViable)")
            if !isViable {
                disconnect()
                scheduleReconnect(reason: "ViabilityChanged to false")
            }

        case let .reconnectSuggested(shouldReconnect):
            log.warning("Websocket recommand reconnect: \(shouldReconnect)")
            if shouldReconnect {
                disconnect()
                scheduleReconnect(reason: "Server suggested reconnect")
            }

        case .cancelled:
            log.warning("WebSocket connection canceled")
            connectionState = .cancelled

        case let .error(error):
            log.error("WebSocket connection err: \(error?.localizedDescription ?? "Unknown error")")
            connectionState = .failed

            // 1) 兼容 Starscream 抛出的 HTTP 升级错误：HTTPUpgradeError
            if let upgrade = error as? HTTPUpgradeError {
                switch upgrade {
                case let .notAnUpgrade(statusCode, _ /* headers */ ):
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

            if JWTValidator.isValid(Config.shared.USER_CONFIG.authToken) {
                EventBus.shared.publish(.notificationReceived(.authTokenFailed))
            }

            return
        }

        scheduleReconnect(reason: "HTTP upgrade failed: \(status)")
    }
}
