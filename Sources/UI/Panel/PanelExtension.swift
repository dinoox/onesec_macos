import ObjectiveC
import SwiftUI

enum TranslatePosition: Equatable {
    case collapse
    case selection
    case bottom
    case above
}

enum PanelType: Equatable {
    case editable
    case translate(TranslatePosition)
    case command
    case notification
    case notificationSystem

    var isTranslate: Bool {
        if case .translate = self { return true }
        return false
    }

    var titleIcon: String {
        switch self {
        case .translate(.selection), .translate(.bottom), .command, .editable:
            return "sparkles"
        default:
            return "mic"
        }
    }

    var canMove: Bool {
        return self != .notificationSystem
    }

    var canFollowScreenChange: Bool {
        if case .translate = self {
            return false
        }

        if case .editable = self {
            return false
        }
        return true
    }
}

enum ExpandDirection {
    case up
    case down
}

extension NSPanel {
    private static var panelTypeKey: UInt8 = 0
    private static var expandDirectionKey: UInt8 = 1
    private static var initialOriginKey: UInt8 = 2
    private static var initializedKey: UInt8 = 3
    private static var wasDraggedKey: UInt8 = 4
    private static var moveObserverKey: UInt8 = 5
    private static var isUpdatingPositionKey: UInt8 = 6

    var panelType: PanelType? {
        get {
            return objc_getAssociatedObject(self, &Self.panelTypeKey) as? PanelType
        }
        set {
            objc_setAssociatedObject(self, &Self.panelTypeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var expandDirection: ExpandDirection? {
        get {
            return objc_getAssociatedObject(self, &Self.expandDirectionKey) as? ExpandDirection
        }
        set {
            objc_setAssociatedObject(self, &Self.expandDirectionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var initialOrigin: NSPoint? {
        get {
            return objc_getAssociatedObject(self, &Self.initialOriginKey) as? NSPoint
        }
        set {
            objc_setAssociatedObject(self, &Self.initialOriginKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var initialized: Bool {
        get {
            return objc_getAssociatedObject(self, &Self.initializedKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &Self.initializedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var wasDragged: Bool {
        get {
            return objc_getAssociatedObject(self, &Self.wasDraggedKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &Self.wasDraggedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var moveObserver: NSObjectProtocol? {
        get {
            return objc_getAssociatedObject(self, &Self.moveObserverKey) as? NSObjectProtocol
        }
        set {
            objc_setAssociatedObject(self, &Self.moveObserverKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var isUpdatingPosition: Bool {
        get {
            return objc_getAssociatedObject(self, &Self.isUpdatingPositionKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &Self.isUpdatingPositionKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func removeMoveObserver() {
        if let observer = moveObserver {
            NotificationCenter.default.removeObserver(observer)
            moveObserver = nil
        }
    }
}

class EditablePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "a":
                return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "c":
                return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
            case "v":
                return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "x":
                return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "z":
                if event.modifierFlags.contains(.shift) {
                    return NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
                } else {
                    return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension NSView {
    func updateTrackingAreasRecursively() {
        updateTrackingAreas()
        for subview in subviews {
            subview.updateTrackingAreasRecursively()
        }
    }
}
