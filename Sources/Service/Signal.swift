//
//  Signal.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation

final class SignalHandler {
    nonisolated(unsafe) static let shared = SignalHandler()
    private let lock = NSLock()
    private var isShuttingDown = false
    
    func setupSignalHandlers() {
        signal(SIGINT) { _ in
            log.info("Receive SIGINT (Ctrl+C)")
            SignalHandler.shared.gracefulShutdown()
        }
        
        signal(SIGTERM) { _ in
            log.info("Receive SIGTERM")
            SignalHandler.shared.gracefulShutdown()
        }
        
        log.info("Signal handler setted")
    }
    
    func gracefulShutdown() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isShuttingDown else { return }
        isShuttingDown = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            log.info("Graceful Shutdown")
            exit(0)
        }
    }
}
