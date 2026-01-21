import SwiftUI
import AVFoundation

/// Control panel for text-to-speech functionality
struct TTSControlPanel: View {
    @Bindable var ttsService: TextToSpeechService
    let onToggle: () -> Void

    @State private var showVoiceSettings = false
    @State private var showSpeedSlider = false

    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause Button
            playPauseButton

            // Speed Control
            speedControl

            // Voice Selection
            voiceButton

            // Stop Button
            if ttsService.isPlaying || ttsService.isPaused {
                stopButton
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
        .popover(isPresented: $showVoiceSettings, arrowEdge: .bottom) {
            VoiceSelectionView(ttsService: ttsService)
                .frame(width: 350, height: 400)
        }
    }

    // MARK: - Play/Pause Button

    private var playPauseButton: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: playPauseIcon)
                    .font(.title3)

                Text(playPauseText)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(minWidth: 100)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var playPauseIcon: String {
        if ttsService.isPaused {
            return "play.fill"
        } else if ttsService.isPlaying {
            return "pause.fill"
        } else {
            return "play.fill"
        }
    }

    private var playPauseText: String {
        if ttsService.isPaused {
            return "Resume"
        } else if ttsService.isPlaying {
            return "Pause"
        } else {
            return "Read Aloud"
        }
    }

    // MARK: - Speed Control

    private var speedControl: some View {
        Menu {
            ForEach(speedPresets, id: \.value) { preset in
                Button {
                    ttsService.rate = preset.value
                } label: {
                    HStack {
                        Text(preset.label)
                        if abs(ttsService.rate - preset.value) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                showSpeedSlider.toggle()
            } label: {
                HStack {
                    Text("Custom Speed...")
                    if showSpeedSlider {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if showSpeedSlider {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speed: \(speedLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(value: Binding(
                        get: { Double(ttsService.rate) },
                        set: { ttsService.rate = Float($0) }
                    ), in: 0.3...2.0, step: 0.1)
                    .frame(width: 200)
                }
                .padding(8)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                Text(speedLabel)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .menuStyle(.borderlessButton)
    }

    private var speedLabel: String {
        String(format: "%.1fx", ttsService.rate)
    }

    private let speedPresets: [(label: String, value: Float)] = [
        ("0.5x (Slow)", 0.5),
        ("0.75x", 0.75),
        ("1.0x (Normal)", AVSpeechUtteranceDefaultSpeechRate),
        ("1.25x", 1.25),
        ("1.5x (Fast)", 1.5),
        ("2.0x (Very Fast)", 2.0)
    ]

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button {
            showVoiceSettings = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.wave.2")
                Text(voiceName)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private var voiceName: String {
        ttsService.selectedVoice.rawValue
    }

    // MARK: - Stop Button

    private var stopButton: some View {
        Button {
            ttsService.stop()
        } label: {
            Image(systemName: "stop.fill")
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

// MARK: - Voice Selection View

struct VoiceSelectionView: View {
    @Bindable var ttsService: TextToSpeechService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.wave.2.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    Text("Select Voice")
                        .font(.headline)

                    Spacer()
                }

                Text("Choose a voice for reading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            // Voice List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(TextToSpeechService.Voice.allCases) { voice in
                        VoiceRow(
                            voice: voice,
                            isSelected: ttsService.selectedVoice == voice
                        ) {
                            ttsService.selectedVoice = voice
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Voice Row

struct VoiceRow: View {
    let voice: TextToSpeechService.Voice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Radio button
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                // Voice info
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Text(voice.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var ttsService = TextToSpeechService()

        var body: some View {
            VStack {
                TTSControlPanel(ttsService: ttsService) {
                    ttsService.togglePlayPause(text: "This is a test of the text to speech system.")
                }

                Spacer()
            }
        }
    }

    return PreviewWrapper()
}
