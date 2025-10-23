//
//  ConnectionCenter.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/15.
//

import AppKit
import Combine
import Foundation

class ConnectionCenter: @unchecked Sendable {
    static let shared = ConnectionCenter()

    private var wssClient: WebSocketAudioStreamer = .init()
    private var udsClient: UDSClient = .init()
    private var permissionClient: PermissionService = .shared
    private var networkClient: NetworkService = .shared

    @Published var wssState: ConnState = .disconnected
    @Published var udsState: ConnState = .disconnected
    @Published var permissionsState: [PermissionType: PermissionStatus] = [:]
    @Published var networkStatus: NetworkStatus = .unavailable

    @Published var currentMouseScreen: NSScreen? = nil
    @Published var isAuthed: Bool = true

    private var cancellables = Set<AnyCancellable>()

    private init() {
        udsClient.connect()
        wssClient.connect()
        bind()
        initScreen()
        initEventListener()
    }

    private func bind() {
        bind(wssClient.$connectionState, to: \.wssState)
        bind(udsClient.$connectionState, to: \.udsState)
        bind(permissionClient.$permissionsState, to: \.permissionsState)
        bind(networkClient.$networkStatus, to: \.networkStatus)
    }

    func canRecord() -> Bool {
        isWssServerConnected() && hasPermissions()
    }

    func isWssServerConnected() -> Bool {
        wssClient.connectionState == .connected
    }

    func hasPermissions() -> Bool {
        guard permissionsState.count != 0 else { return false }
        return permissionsState.values.allSatisfy { $0 == .granted }
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

                let stateName = String(describing: keyPath)
                    .components(separatedBy: ".")
                    .last!
                    .replacingOccurrences(of: ">", with: "")

                log.debug("\("[\(stateName)]".green) → \("\(newValue)".green)")
            }
            .store(in: &cancellables)
    }

    private func initScreen() {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        }) {
            currentMouseScreen = screen
        }
    }

    private func initEventListener() {
        EventBus.shared.eventSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                if case .notificationReceived(.authTokenFailed) = event {
                    self?.isAuthed = false
                }
            }
            .store(in: &cancellables)
    }
}
