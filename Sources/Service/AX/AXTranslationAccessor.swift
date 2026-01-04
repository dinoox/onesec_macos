import AppKit
import Combine
import SwiftUI

@MainActor
class AXTranslationAccessor {
    private static var mouseDownMonitor: Any?
    private static var mouseUpMonitor: Any?
    private static var pasteboardText = ""
    private static var translationPanelID: UUID?
    private static var mouseDownPoint: NSPoint?
    private static var cancellable: AnyCancellable?

    static func setupMouseUpListener() {
        cancellable = Config.shared.$CURRENT_PERSONA
            .sink { persona in
                if persona?.name == "翻译" {
                    startMonitoring()
                } else {
                    stopMonitoring()
                }
            }
    }

    private static func startMonitoring() {
        guard mouseDownMonitor == nil else { return }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            Task { @MainActor in
                mouseDownPoint = NSEvent.mouseLocation
                pasteboardText = NSPasteboard.general.string(forType: .string) ?? ""
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task { @MainActor in
                guard let downPoint = mouseDownPoint else { return }
                mouseDownPoint = nil

                let upPoint = NSEvent.mouseLocation
                let distance = hypot(upPoint.x - downPoint.x, upPoint.y - downPoint.y)

                // 25 约为两个中文字符宽度
                guard distance > 25 else {
                    OverlayController.shared.hideOverlays(.translate(.collapse))
                    return
                }

                await endTranslationRecording(mousePoint: upPoint, direction: upPoint.y > downPoint.y ? .up : .down)
            }
        }
    }

    private static func stopMonitoring() {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
        mouseDownPoint = nil
    }

    private static func endTranslationRecording(mousePoint: NSPoint, direction: ExpandDirection) async {
        guard let text = await ContextService.getSelectedText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text != pasteboardText
        else {
            log.info("No text to translate")
            return
        }

        translationPanelID = OverlayController.shared.showOverlayAbovePoint(point: mousePoint, content: { panelID in
            LazyTranslationCard(
                panelID: panelID,
                title: "执行结果",
                content: text,
                isCompactMode: true,
                expandDirection: direction
            )
        }, panelType: .translate(.collapse), expandDirection: direction)
    }
}
