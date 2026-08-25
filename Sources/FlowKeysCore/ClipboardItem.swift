import Foundation

/// One captured clipboard entry.
public struct ClipboardItem: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let capturedAt: Date
    /// Bundle identifier of the app the text was copied from, when known.
    public let sourceApp: String?
    /// Pinned items are never evicted when the history fills up.
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        capturedAt: Date = Date(),
        sourceApp: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
        self.sourceApp = sourceApp
        self.isPinned = isPinned
    }

    /// Single-line preview for the overlay, with whitespace collapsed.
    public func preview(maxLength: Int = 60) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if collapsed.count <= maxLength { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }

    /// "12 words · 3 lines" style annotation shown under the preview.
    public var summary: String {
        let lines = text.components(separatedBy: .newlines).count
        let chars = text.count
        if lines > 1 { return "\(chars) chars · \(lines) lines" }
        return "\(chars) chars"
    }
}
