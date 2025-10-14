//
//  Signal.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation

@MainActor
class SignalHandler {
    static let shared = SignalHandler()
    private var isShuttingDown = false
    
    func setupSignalHandlers() {
        signal(SIGINT) { _ in
            log.info("收到 SIGINT 信号 (Ctrl+C)")
            SignalHandler.shared.gracefulShutdown()
        }
        
        signal(SIGTERM) { _ in
            log.info("收到 SIGTERM 信号 (系统终止)")
            SignalHandler.shared.gracefulShutdown()
        }
        
        signal(SIGHUP) { _ in
            log.info("收到 SIGHUP 信号 (终端关闭)")
            SignalHandler.shared.gracefulShutdown()
        }
        
        signal(SIGQUIT) { _ in
            log.info("收到 SIGQUIT 信号")
            SignalHandler.shared.gracefulShutdown()
        }
        
        log.info("信号处理器设置完成")
    }
    
    func gracefulShutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        
        log.info("开始优雅关闭...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            log.info("优雅关闭完成")
            exit(0)
        }
    }
}
