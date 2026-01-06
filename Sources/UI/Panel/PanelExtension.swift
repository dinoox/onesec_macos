import ObjectiveC
import SwiftUI

enum PanelPosition: Equatable {
    case collapse
    case selection
    case bottom
    case above
}

enum PanelType: Equatable {
    case editable
    case translate(PanelPosition)
    case command(PanelPosition)
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

    var canShowStatusPanel: Bool {
        switch self {
        case .translate(.bottom), .command(.bottom), .notification, .notificationSystem:
            return true
        default:
            return false
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

// MARK: - macOS 10.15 compatible hover implementation

class HoverTrackingView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect,
        ]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

struct HoverView: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context _: Context) -> HoverTrackingView {
        let view = HoverTrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverTrackingView, context _: Context) {
        nsView.onHover = onHover
    }
}

extension View {
    @ViewBuilder
    func compatibleHover(useBackground: Bool = false, onHover: @escaping (Bool) -> Void) -> some View {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 11 || useBackground {
            background(HoverView(onHover: onHover))
        } else {
            self.onHover(perform: onHover)
        }
    }
}
