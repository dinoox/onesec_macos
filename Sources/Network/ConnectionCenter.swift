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
        udsClient = UDSClient()
        udsClient!.connect()

        wssClient = WebSocketAudioStreamer()
        wssClient!.connect()
    }
}
