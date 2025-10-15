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

//        wssClient = WebSocketAudioStreamer()
//        wssClient!.connect()
    }

    func sendStartRecording(appInfo: AppInfo? = nil, focusContext: FocusContext? = nil, focusElementInfo: FocusElementInfo? = nil, recognitionMode: String = "normal") {
        wssClient?.sendStartRecording(appInfo: appInfo, focusContext: focusContext, focusElementInfo: focusElementInfo, recognitionMode: recognitionMode)
        udsClient?.sendStartRecording(recognitionMode: recognitionMode)
    }

    func sendStopRecording() {
        wssClient?.sendStopRecording()
        udsClient?.sendStopRecording()
    }

    func sendModeUpgrade(fromMode: String, toMode: String, focusContext: FocusContext? = nil) {
        wssClient?.sendModeUpgrade(fromMode: fromMode, toMode: toMode, focusContext: focusContext)
        udsClient?.sendModeUpgrade(fromMode: fromMode, toMode: toMode, focusContext: focusContext)
    }

    func sendAuthTokenFailed(reason: String, statusCode: Int? = nil) {
        udsClient?.sendAuthTokenFailed(reason: reason, statusCode: statusCode)
    }
}
