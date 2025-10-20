//
//  ConnectionCenter.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import Combine
import Foundation

class ConnectionCenter: @unchecked Sendable {
    static let shared = ConnectionCenter()

    private var wssClient: WebSocketAudioStreamer = .init()
    private var udsClient: UDSClient = .init()
    private var permissionClient: PermissionManager = .shared

    @Published var wssState: ConnState = .disconnected
    @Published var udsState: ConnState = .disconnected
    @Published var permissionStatusList: [PermissionType: PermissionStatus] = [:]

    private var cancellables = Set<AnyCancellable>()

    private init() {
        udsClient.connect()
        wssClient.connect()
        bind()
    }

    private func bind() {
        bind(wssClient.$connectionState, to: \.wssState)
        bind(udsClient.$connectionState, to: \.udsState)
        bind(permissionClient.$permissionStatusList, to: \.permissionStatusList)
    }

    func canRecord() -> Bool {
        isWssServerConnected() && hasAllPermissions()
    }

    func isWssServerConnected() -> Bool {
        wssClient.connectionState == .connected
    }

    func hasAllPermissions() -> Bool {
        permissionStatusList.values.allSatisfy { $0 == .granted }
    }
}

extension ConnectionCenter {
    private func bind<T>(
        _ publisher: Published<T>.Publisher,
        to keyPath: ReferenceWritableKeyPath<ConnectionCenter, T>,
    ) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?[keyPath: keyPath] = newValue
                log.info("State [\(keyPath)] Sync to \(newValue)")
            }
            .store(in: &cancellables)
    }
}
