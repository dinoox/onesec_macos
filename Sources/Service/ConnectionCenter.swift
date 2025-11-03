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
    private var permissionService: PermissionService = .shared
    private var networkService: NetworkService = .shared
    private var inputSerive: InputController?

    @Published var wssState: ConnState = .disconnected
    @Published var udsState: ConnState = .disconnected
    @Published var permissionsState: [PermissionType: PermissionStatus] = [:]
    @Published var networkState: NetworkStatus = .unavailable
    @Published var audioRecorderState: RecordState = .idle

    @Published var currentMouseScreen: NSScreen? = nil
    @Published var isAuthed: Bool = JWTValidator.isValid(Config.shared.AUTH_TOKEN)

    private var cancellables = Set<AnyCancellable>()

    private init() {
        bind()
        initScreen()
        initEventListener()
    }

    func initialize() {
        udsClient.connect()
        wssClient.connect()
    }

    private func bind() {
        bind(wssClient.$connectionState, to: \.wssState)
        bind(udsClient.$connectionState, to: \.udsState)
        bind(permissionService.$permissionsState, to: \.permissionsState)
        bind(networkService.$networkStatus, to: \.networkState)
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

    func connectWss() {
        wssClient.connect()
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

        $permissionsState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePermissionChange()
            }
            .store(in: &cancellables)
    }

    private func handlePermissionChange() {
        let hasPermissions = hasPermissions()
        if hasPermissions, inputSerive == nil {
            inputSerive = InputController()
            bind(inputSerive!.audioRecorder.$recordState, to: \.audioRecorderState)
        } else if !hasPermissions, inputSerive != nil {
            log.warning("Permission Revoked, Cleaning InputService")
            inputSerive = nil
        }
    }
}
