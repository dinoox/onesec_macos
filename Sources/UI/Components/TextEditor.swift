import AppKit
import SwiftUI
import Highlightr

struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var language: String
    var theme: String
    var fontSize: CGFloat
    var isEditable: Bool
    var backgroundColor: NSColor
    var minHeight: CGFloat
    var maxHeight: CGFloat
    
    init(
        text: Binding<String>,
        contentHeight: Binding<CGFloat>,
        language: String = "bash",
        theme: String = "atom-one-dark",
        fontSize: CGFloat = 14,
        isEditable: Bool = true,
        backgroundColor: NSColor = NSColor(white: 0.15, alpha: 1.0),
        minHeight: CGFloat = 0,
        maxHeight: CGFloat = 300
    ) {
        self._text = text
        self._contentHeight = contentHeight
        self.language = language
        self.theme = theme
        self.fontSize = fontSize
        self.isEditable = isEditable
        self.backgroundColor = backgroundColor
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        
        guard let highlightr = Highlightr() else {
            textView.string = text
            return scrollView
        }
        
        highlightr.setTheme(to: theme)
        
        let textStorage = CodeAttributedString(highlightr: highlightr)
        textStorage.language = language
        textStorage.highlightr.theme.setCodeFont(NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular))
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = textView.textContainer
        layoutManager.addTextContainer(textContainer!)
        
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        textView.didChangeText()
        
        scrollView.backgroundColor = backgroundColor
        scrollView.drawsBackground = true
        
        DispatchQueue.main.async {
            context.coordinator.updateHeight(textView: textView, scrollView: scrollView)
        }
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            textView.string = text
            textView.didChangeText()
        }
        
        // 更新主题
        if let textStorage = textView.textStorage as? CodeAttributedString {
            if context.coordinator.currentTheme != theme {
                textStorage.highlightr.setTheme(to: theme)
                textView.backgroundColor = backgroundColor
                scrollView.backgroundColor = backgroundColor
                context.coordinator.currentTheme = theme
                // 重新应用高亮
                textView.string = text
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        var currentTheme: String = ""
        
        init(_ parent: CodeTextEditor) {
            self.parent = parent
            self.currentTheme = parent.theme
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            if let scrollView = textView.enclosingScrollView {
                updateHeight(textView: textView, scrollView: scrollView)
            }
        }
        
        func updateHeight(textView: NSTextView, scrollView: NSScrollView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let padding = textView.textContainerInset.height * 2
            let calculatedHeight = usedRect.height + padding + 4
            
            let boundedHeight = min(max(calculatedHeight, parent.minHeight), parent.maxHeight)
            
            DispatchQueue.main.async {
                self.parent.contentHeight = boundedHeight
                print("contentHeight: \(boundedHeight)")
            }
        }
    }
}

struct SyntaxTextEditor: View {
    @Binding var text: String
    @State private var contentHeight: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    var language: String
    var lightTheme: String
    var darkTheme: String
    var fontSize: CGFloat
    var isEditable: Bool
    var minHeight: CGFloat
    var maxHeight: CGFloat
    
    init(
        text: Binding<String>,
        language: String = "bash",
        lightTheme: String = "github",
        darkTheme: String = "dracula",
        fontSize: CGFloat = 14,
        isEditable: Bool = true,
        minHeight: CGFloat = 0,
        maxHeight: CGFloat = 300
    ) {
        self._text = text
        self.language = language
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.fontSize = fontSize
        self.isEditable = isEditable
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }
    
    private var currentTheme: String {
        colorScheme == .dark ? darkTheme : lightTheme
    }
    
    var body: some View {
        CodeTextEditor(
            text: $text,
            contentHeight: $contentHeight,
            language: language,
            theme: currentTheme,
            fontSize: fontSize,
            isEditable: isEditable,
            backgroundColor: NSColor(Color.overlayCodeBackground),
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        .frame(height: contentHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

