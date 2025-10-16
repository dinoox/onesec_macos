//
//  ConnectionCenter.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Foundation

actor ConnectionCenter {
    static let shared = ConnectionCenter()

    private var wssClient: WebSocketAudioStreamer?
    private var udsClient: UDSClient?

    private init() {
        // 初始化 UDS 客户端并连接
        udsClient = UDSClient()
        udsClient!.connect()

        // 初始化 WebSocket 客户端（订阅 EventBus）
        wssClient = WebSocketAudioStreamer()
        wssClient!.connect()
    }
}
