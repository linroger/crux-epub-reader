import SwiftUI

/// Thin horizontal scrubber at the bottom of the reader window. Renders
/// per-chapter progress (filled accent for completed chapters, partial
/// accent for the current chapter) and lets the user tap or drag to
/// navigate to any chapter.
///
/// The scrubber is intentionally shallow (~6 pt) so it doesn't dominate
/// the chrome — its primary affordance is the hover preview that
/// surfaces the destination chapter title.
struct ProgressScrubber: View {
    let chapters: [Chapter]
    let currentChapterIndex: Int
    let currentScrollPosition: Double
    let onSeek: (Int) -> Void

    @State private var hoverFraction: Double?
    @State private var isPressed: Bool = false

    /// Chapter index the user's cursor is hovering over (or dragging
    /// to). Used by the tooltip and to compute the navigation target.
    private var hoverChapterIndex: Int? {
        guard let fraction = hoverFraction else { return nil }
        let raw = Int(fraction * Double(max(1, chapters.count)))
        return min(max(raw, 0), chapters.count - 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = geo.size.width
                let chapterWidth = width / CGFloat(max(1, chapters.count))

                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))

                    // Completed chapters
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: chapterWidth * CGFloat(currentChapterIndex))

                    // Current chapter progress on top of completed
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: chapterWidth * CGFloat(currentChapterIndex)
                               + chapterWidth * CGFloat(currentScrollPosition))

                    // Chapter divisions
                    HStack(spacing: 0) {
                        ForEach(0..<chapters.count, id: \.self) { i in
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: chapterWidth)
                                .overlay(alignment: .trailing) {
                                    if i < chapters.count - 1 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.18))
                                            .frame(width: 1)
                                    }
                                }
                        }
                    }

                    // Hover indicator — small caret under the cursor
                    if let fraction = hoverFraction {
                        let x = CGFloat(fraction) * width
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let fraction = max(0, min(1, location.x / max(width, 1)))
                        hoverFraction = fraction
                    case .ended:
                        hoverFraction = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isPressed = true
                            let fraction = max(0, min(1, value.location.x / max(width, 1)))
                            hoverFraction = fraction
                        }
                        .onEnded { value in
                            isPressed = false
                            let fraction = max(0, min(1, value.location.x / max(width, 1)))
                            let target = Int(fraction * Double(max(1, chapters.count)))
                            let bounded = min(max(target, 0), chapters.count - 1)
                            onSeek(bounded)
                            hoverFraction = nil
                        }
                )
                .help(hoverTooltip)
                .accessibilityLabel("Reading progress")
                .accessibilityValue("Chapter \(currentChapterIndex + 1) of \(chapters.count)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        if currentChapterIndex < chapters.count - 1 {
                            onSeek(currentChapterIndex + 1)
                        }
                    case .decrement:
                        if currentChapterIndex > 0 {
                            onSeek(currentChapterIndex - 1)
                        }
                    @unknown default: break
                    }
                }
            }
            .frame(height: isPressed ? 8 : 6)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
    }

    /// Tooltip text shown while hovering — surfaces the destination
    /// chapter title so users see where a click would land.
    private var hoverTooltip: String {
        guard let idx = hoverChapterIndex, idx < chapters.count else {
            return "Chapter \(currentChapterIndex + 1) of \(chapters.count)"
        }
        let title = chapters[idx].title.isEmpty ? "Chapter \(idx + 1)" : chapters[idx].title
        return "Jump to: \(title)"
    }
}
