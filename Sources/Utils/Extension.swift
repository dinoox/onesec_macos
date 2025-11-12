//
//  extension.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/29.
//

extension String {
    var cleaned: String {
        self.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var formattedCommand: String {
        self.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " && \\\n")
    }
}
