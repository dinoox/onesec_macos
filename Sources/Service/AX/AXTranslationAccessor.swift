import AppKit
import Combine
import SwiftUI

@MainActor
class AXTranslationAccessor {
    private static var mouseDownMonitor: Any?
    private static var mouseUpMonitor: Any?

    private static var currentSelectedText: String = ""
    private static var pasteboardText = ""

    private static var translationPanelID: UUID?
    private static var hasMouseDown: Bool = false
    private static var mouseDownPoint: NSPoint?

    static func setupMouseUpListener() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            Task { @MainActor in
                if Config.shared.TEXT_PROCESS_MODE != .translate {
                    return
                }
                hasMouseDown = true
                mouseDownPoint = NSEvent.mouseLocation
                pasteboardText = NSPasteboard.general.string(forType: .string) ?? ""
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task { @MainActor in
                guard hasMouseDown, let downPoint = mouseDownPoint else { return }
                hasMouseDown = false
                mouseDownPoint = nil

                let mouseUpPoint = NSEvent.mouseLocation
                let distance = sqrt(pow(mouseUpPoint.x - downPoint.x, 2) + pow(mouseUpPoint.y - downPoint.y, 2))

                // let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                // let twoChineseWidth = ("中" as NSString).size(withAttributes: [.font: font]).width * 2

                guard distance > 25 else {
                    reset()
                    return
                }

                await endTranslationRecording(mousePoint: mouseUpPoint)
            }
        }
    }

    private static func endTranslationRecording(mousePoint: NSPoint) async {
        let text = await ContextService.getSelectedText()
        if text == nil ||
            text!.isEmpty ||
            text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            text == pasteboardText
        {
            log.info("No text to translate")
            reset()
            return
        }
        currentSelectedText = text!

        OverlayController.shared.hideAllOverlays()
        translationPanelID = OverlayController.shared.showOverlayAbovePoint(point: mousePoint) { panelID in
            LazyTranslationCard(
                panelID: panelID,
                title: "识别结果",
                content: currentSelectedText,
                isCompactMode: true,
                expandDirection: .down
            )
        }

        // 清空记录
        currentSelectedText = ""
    }

    private static func reset() {
        if translationPanelID != nil {
            OverlayController.shared.hideOverlay(uuid: translationPanelID!)
            translationPanelID = nil
        }
        currentSelectedText = ""
    }
}
