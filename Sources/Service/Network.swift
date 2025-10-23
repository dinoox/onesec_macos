//
//  Network.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/23.
//

import Combine
import Foundation
import Network

enum NetworkStatus: Equatable {
    case available
    case unavailable
}

final class NetworkService: ObservableObject, @unchecked Sendable {
    static let shared = NetworkService()
    
    @Published var networkStatus: NetworkStatus = .unavailable
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.onesec.network.monitor")
    
    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus: NetworkStatus = path.status == .satisfied ? .available : .unavailable
            log.info("Network status changed to: \(newStatus)")
            DispatchQueue.main.async {
                self?.networkStatus = newStatus
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}


