import FlowKeysCore
import SwiftUI

/// The floating picker. Deliberately minimal: it appears mid-keystroke and
/// has to be readable in the time it takes to tap V again.
struct OverlayView: View {
    let items: [ClipboardItem]
    let selection: Int
    /// Type-to-filter text, shown as a header when non-empty.
    var query: String = ""

    /// Rows to show around the selection. The full history stays reachable by
    /// continuing to tap V; showing 50 rows next to the caret would not be.
    private let windowSize = 5

    private var visibleRange: Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        let half = windowSize / 2
        var start = selection - half
        start = max(0, min(start, max(0, items.count - windowSize)))
        let end = min(items.count, start + windowSize)
        return start..<end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !query.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9, weight: .bold))
                    Text(query)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    Text(items.isEmpty ? "no matches" : "\(items.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(items.isEmpty ? Color.secondary : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            if items.isEmpty {
                Text(query.isEmpty ? "Clipboard history is empty" : "Nothing matches \u{201C}\(query)\u{201D}")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }

            ForEach(visibleRange, id: \.self) { index in
                row(for: items[index], index: index)
            }

            if items.count > windowSize || !query.isEmpty {
                HStack(spacing: 4) {
                    Text("\(selection + 1) of \(items.count)")
                    Spacer()
                    Text("⌘V cycle · 1-9 jump · type to filter · esc")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)
            }
        }
        .padding(6)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }

    @ViewBuilder
    private func row(for item: ClipboardItem, index: Int) -> some View {
        let isSelected = index == selection
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                .frame(width: 16, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview())
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? .white : .primary)
                if isSelected {
                    Text(item.summary)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            Spacer(minLength: 0)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isSelected ? 5 : 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
