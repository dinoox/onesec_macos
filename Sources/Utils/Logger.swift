//
//  Logger.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/14.
//

import Foundation
import SwiftyBeaver

enum Logger {
    static let log: SwiftyBeaver.Type = {
        let log = SwiftyBeaver.self
        let console = ConsoleDestination()
        console.format = "$DHH:mm:ss$d $L $M"
//        console.logPrintWay = .logger(subsystem: "Main", category: "UI")
        log.addDestination(console)
        return log
    }()
}

let log = Logger.log
