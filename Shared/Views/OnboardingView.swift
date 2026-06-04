import SwiftUI
import SwiftData

/// First-launch welcome experience that explains the AI annotation
/// workflow, key keyboard shortcuts, and where to configure providers.
///
/// Dismissing the sheet flips `AppSettings.hasSeenOnboarding` so it never
/// shows again. Users can re-trigger it from the About tab in Settings.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Mutated when the sheet finishes so the host can persist the flag.
    var onFinish: () -> Void

    @State private var currentPage: Int = 0

    /// Animation used for page transitions; honors Reduce Motion.
    private var pageAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "book.fill",
            title: "Welcome to Crux",
            subtitle: "An AI-native EPUB reader for deep, attentive reading.",
            body: "Crux pairs a clean reading experience with margin-grade AI annotations, persistent notes, and a polished library — all in a single native macOS app."
        ),
        OnboardingPage(
            symbol: "highlighter",
            title: "Highlight and Think",
            subtitle: "Select any passage to start a thread.",
            body: "Highlights are saved per-book with categories you can customize. Open the thread panel to ask an AI provider for a substantive margin note, then follow up with questions to dig deeper.",
            tips: [
                Tip(symbol: "command", label: "⌘O", text: "Open an EPUB"),
                Tip(symbol: "magnifyingglass", label: "⌘F", text: "Search in current book"),
                Tip(symbol: "questionmark.circle", label: "⌘/", text: "All keyboard shortcuts")
            ]
        ),
        OnboardingPage(
            symbol: "cpu",
            title: "Bring Your Own AI",
            subtitle: "Claude, OpenAI, Apple Intelligence, or any compatible endpoint.",
            body: "API keys are stored in the system Keychain — never in plain text. You can switch providers at any time from Settings → AI Providers, and validate connectivity with the built-in test button.",
            tips: [
                Tip(symbol: "lock.shield", label: "Keychain", text: "Keys never touch SwiftData"),
                Tip(symbol: "arrow.triangle.2.circlepath", label: "Retry", text: "Transient errors auto-retry")
            ]
        ),
        OnboardingPage(
            symbol: "chart.line.uptrend.xyaxis",
            title: "Track Your Reading",
            subtitle: "Goals, streaks, statistics, collections.",
            body: "Crux tracks how much you read, awards streaks for consistency, and lets you organize books into collections. Everything stays on-device unless you choose to back up.",
            tips: [
                Tip(symbol: "calendar", label: "⌘⇧G", text: "Reading goals"),
                Tip(symbol: "chart.bar", label: "⌘⇧S", text: "Statistics"),
                Tip(symbol: "flame", label: "⌘⇧T", text: "Streaks & achievements")
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 24)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif
            .frame(minHeight: 360)

            Divider()

            // Footer with controls
            HStack {
                // Page dots (macOS)
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }

                Spacer()

                if currentPage > 0 {
                    Button("Back") {
                        withAnimation(pageAnimation) { currentPage -= 1 }
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                }

                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation(pageAnimation) { currentPage += 1 }
                    } label: {
                        Text("Next")
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                } else {
                    Button {
                        finish()
                    } label: {
                        Text("Start Reading")
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 520)
        .background(.background)
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let subtitle: String
    let body: String
    var tips: [Tip] = []
}

private struct Tip: Identifiable {
    let id = UUID()
    let symbol: String
    let label: String
    let text: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 18) {
            // Hero icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.25), .accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: page.symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(page.body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: 460)
                .padding(.horizontal, 8)

            if !page.tips.isEmpty {
                VStack(spacing: 10) {
                    ForEach(page.tips) { tip in
                        HStack(spacing: 12) {
                            Image(systemName: tip.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 22, height: 22)
                            Text(tip.label)
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(minWidth: 64, alignment: .leading)
                            Text(tip.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .frame(maxWidth: 460)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .frame(width: 640, height: 520)
}
