import ObjectiveC
import SwiftUI

enum PanelType {
    case editable
    case translate
    case command
    case notification
    case notificationSystem
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
