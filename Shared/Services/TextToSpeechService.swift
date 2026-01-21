import Foundation
import AVFoundation

/// Service for local text-to-speech using MLX models on Apple Silicon
///
/// This service uses the mlx-audio framework for high-quality, local TTS
/// that runs efficiently on Apple Silicon using the Neural Engine.
///
/// **Package**: mlx-audio by Blaizzy
/// **Sources**:
/// - [GitHub - Blaizzy/mlx-audio](https://github.com/Blaizzy/mlx-audio)
/// - [Swift Package Index](https://swiftpackageindex.com/Blaizzy/mlx-audio)
/// - [MLX Framework](https://ml-explore.github.io/mlx/)
@Observable
final class TextToSpeechService {
    // MARK: - Voice Types

    /// Available MLX TTS voice models
    enum Voice: String, CaseIterable, Identifiable {
        case conversationalA = "Conversational A"
        case conversationalB = "Conversational B"
        case narrative = "Narrative"
        case expressive = "Expressive"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .conversationalA:
                return "Natural conversational tone, voice A"
            case .conversationalB:
                return "Natural conversational tone, voice B"
            case .narrative:
                return "Clear narration style, ideal for books"
            case .expressive:
                return "Expressive and dynamic delivery"
            }
        }
    }

    // MARK: - Properties

    /// Current reading state
    var isPlaying = false
    var isPaused = false
    var isLoading = false

    /// Selected voice model
    var selectedVoice: Voice = .narrative {
        didSet {
            if selectedVoice != oldValue {
                // Recreate session with new voice
                Task {
                    await initializeSession()
                }
            }
        }
    }

    /// Reading speed (0.5 - 2.0, default 1.0)
    var rate: Float = 1.0 {
        didSet {
            rate = min(max(rate, 0.5), 2.0)
        }
    }

    /// Current text being read
    private var currentText: String?

    /// Task handle for cancellation
    private var speakingTask: Task<Void, Never>?

    /// Callback for when speech is finished
    var onFinished: (() -> Void)?

    /// Callback for progress updates
    var onProgress: ((String) -> Void)?

    // MARK: - MLX Session
    // Note: Actual MLX session would be initialized here
    // For now, we'll use AVSpeech as fallback until mlx-audio is added
    private let fallbackSynthesizer = AVSpeechSynthesizer()
    private var fallbackVoice: AVSpeechSynthesisVoice?

    // MARK: - Initialization

    init() {
        // Initialize with best available voice
        fallbackVoice = AVSpeechSynthesisVoice(language: "en-US")

        Task {
            await initializeSession()
        }
    }

    // MARK: - Session Management

    /// Initialize or reinitialize the TTS session
    private func initializeSession() async {
        isLoading = true

        // TODO: When mlx-audio package is added, initialize here:
        // Example from mlx-audio documentation:
        //
        // do {
        //     let session = try await MarvisSession(voice: .conversationalA)
        //     self.mlxSession = session
        // } catch {
        //     errorHandler.handle(
        //         AppError.ttsInitializationFailed(error.localizedDescription),
        //         context: "initializeMLXSession"
        //     )
        // }

        // For now, just use fallback
        await MainActor.run {
            isLoading = false
        }
    }

    // MARK: - Public Methods

    /// Start speaking the given text
    @MainActor
    func speak(text: String) {
        guard !text.isEmpty else { return }

        currentText = text

        // Cancel any existing speech
        stop()

        // Start new speech task
        speakingTask = Task {
            await performSpeak(text: text)
        }

        isPlaying = true
        isPaused = false
    }

    /// Perform the actual speech synthesis
    private func performSpeak(text: String) async {
        // TODO: When mlx-audio is added, use streaming generation:
        //
        // do {
        //     for try await chunk in session.stream(text: text) {
        //         await MainActor.run {
        //             onProgress?("Processing chunk: \(chunk.sampleCount) samples")
        //         }
        //     }
        //     await MainActor.run {
        //         isPlaying = false
        //         onFinished?()
        //     }
        // } catch {
        //     await MainActor.run {
        //         isPlaying = false
        //         errorHandler.handle(
        //             AppError.ttsSynthesisFailed(error.localizedDescription),
        //             context: "performSpeak"
        //         )
        //     }
        // }

        // Fallback to AVSpeech for now
        await MainActor.run {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = fallbackVoice
            utterance.rate = rate * AVSpeechUtteranceDefaultSpeechRate
            fallbackSynthesizer.speak(utterance)
        }
    }

    /// Pause speech
    @MainActor
    func pause() {
        guard isPlaying, !isPaused else { return }

        // TODO: Implement pause for MLX audio
        // For now, use fallback
        fallbackSynthesizer.pauseSpeaking(at: .word)
        isPaused = true
    }

    /// Resume speech
    @MainActor
    func resume() {
        guard isPaused else { return }

        // TODO: Implement resume for MLX audio
        // For now, use fallback
        fallbackSynthesizer.continueSpeaking()
        isPaused = false
    }

    /// Stop speech
    @MainActor
    func stop() {
        speakingTask?.cancel()
        speakingTask = nil

        // TODO: Stop MLX session
        // For now, use fallback
        fallbackSynthesizer.stopSpeaking(at: .immediate)

        isPlaying = false
        isPaused = false
        currentText = nil
    }

    /// Toggle play/pause
    @MainActor
    func togglePlayPause(text: String? = nil) {
        if isPlaying {
            if isPaused {
                resume()
            } else {
                pause()
            }
        } else if let text = text {
            speak(text: text)
        }
    }

    // MARK: - Voice Information

    /// Get human-readable language name
    static func languageName(for code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code
    }
}
