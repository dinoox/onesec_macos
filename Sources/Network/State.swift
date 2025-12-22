import Foundation

enum ConnState: Equatable {
    case preparing
    case disconnected
    case connecting
    case failed
    case connected
    case cancelled
    case manualDisconnected // 手动断开
}
