import AppKit
import SwiftUI

struct SyntaxOption {
    var word: String
    var color: NSColor
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    static var `default`: [SyntaxOption] {
        return [
            // Keywords
            SyntaxOption(word: "struct", color: .systemBlue),
            SyntaxOption(word: "class", color: .systemBlue),
            SyntaxOption(word: "enum", color: .systemBlue),
            SyntaxOption(word: "static", color: .systemPink),
            SyntaxOption(word: "func", color: .systemPink),
            SyntaxOption(word: "case", color: .systemPink),
            SyntaxOption(word: "mutating", color: .systemPink),
            SyntaxOption(word: "nonmutating", color: .systemPink),
            SyntaxOption(word: "let", color: .systemPink),
            SyntaxOption(word: "var", color: .systemPink),
            SyntaxOption(word: "return", color: .systemPink),
            SyntaxOption(word: "protocol", color: .systemPink),
            SyntaxOption(word: "extension", color: .systemPink),
            SyntaxOption(word: "private", color: .systemPink),
            SyntaxOption(word: "public", color: .systemPink),
            SyntaxOption(word: "internal", color: .systemPink),

            // Types
            SyntaxOption(word: "Int", color: .systemPink),
            SyntaxOption(word: "String", color: .systemPink),
            SyntaxOption(word: "Bool", color: .systemPink),
            SyntaxOption(word: "Double", color: .systemPink),
            SyntaxOption(word: "Float", color: .systemPink),

            // Constants
            SyntaxOption(word: "true", color: .systemPink),
            SyntaxOption(word: "false", color: .systemPink),
            SyntaxOption(word: "nil", color: .systemPink),

            // Compiler Directives
            SyntaxOption(word: "#if", color: .systemOrange),
            SyntaxOption(word: "#else", color: .systemOrange),
            SyntaxOption(word: "#endif", color: .systemOrange),

            // Protocols
            SyntaxOption(word: "Identifiable", color: .systemPink),
            SyntaxOption(word: "Hashable", color: .systemPink),
            SyntaxOption(word: "Equatable", color: .systemPink),
            SyntaxOption(word: "Codable", color: .systemPink),
            SyntaxOption(word: "Encodable", color: .systemPink),
            SyntaxOption(word: "Decodable", color: .systemPink),
        ]
    }
}

protocol Themeable {
    var syntaxOptions: [SyntaxOption] { get }
    var backgroundColor: NSColor { get }
}

struct EditorTheme: Identifiable, Themeable {
    var id = UUID()
    var name: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    var syntaxOptions: [SyntaxOption]
    var backgroundColor: NSColor = .textBackgroundColor

    static var `default`: EditorTheme {
        .init(name: "Default", syntaxOptions: SyntaxOption.default)
    }
}

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: EditorTheme
    var padding: CGFloat = 12

    @State var textView: NSTextView?

    func makeNSView(context: Context) -> NSView {
        let view = NSTextView.scrollableTextView()
        guard let textView = view.documentView as? NSTextView else { return view }

        DispatchQueue.main.asyncAfter(deadline: .now()) {
            self.textView = textView
            configureTextView(with: context)
        }

        view.contentInsets = .init(top: padding, left: padding, bottom: padding, right: padding)
        view.automaticallyAdjustsContentInsets = false
        return view
    }

    func updateNSView(_: NSView, context _: Context) {
        applySyntaxStyling()
    }

    func applySyntaxStyling() {
        let attributedString = NSMutableAttributedString(string: text)

        let fullRange = NSRange(location: 0, length: text.utf8.count)

        // Default styling for the text.
        attributedString.addAttribute(.font, value: theme.font, range: fullRange)
        attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)

        // Apply styling for the text that matches the a SyntaxOption object.
        for option in theme.syntaxOptions {
            let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: option.word))\\b", options: .caseInsensitive)
            let matches = regex?.matches(in: text, options: [], range: fullRange) ?? []

            for match in matches {
                attributedString.addAttribute(.foregroundColor, value: option.color, range: match.range)
                attributedString.addAttribute(.font, value: option.font, range: match.range)
            }
        }

        textView?.textStorage?.setAttributedString(attributedString)
    }

    func configureTextView(with context: Context) {
        textView?.font = theme.font
        textView?.isEditable = true
        textView?.isRichText = false
        textView?.backgroundColor = theme.backgroundColor

        // Assigning the coordinator as the textView delegate.
        textView?.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

extension CodeEditor {
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var textView: NSTextView?

        init(_ parent: CodeEditor) {
            self.parent = parent
            textView = parent.textView
        }

        // TODO: Add delegate methods for the NSTextView.
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }
    }
}
