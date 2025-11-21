//
//  Extension.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/29.
//

import SwiftUI

extension String {
    var cleaned: String {
        replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var formattedCommand: String {
        split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " && \\\n")
    }
}

extension Text {
    func monospacedDigitIfAvailable() -> Text {
        if #available(macOS 13.0, iOS 15.0, *) {
            return self.fontDesign(.monospaced)
        } else {
            return self
        }
    }
}

extension View {
    @ViewBuilder
    func tryScrollDisabled(_ disabled: Bool) -> some View {
        if #available(macOS 13.0, *) {
            self.scrollDisabled(disabled)
        } else {
            self
        }
    }
}
