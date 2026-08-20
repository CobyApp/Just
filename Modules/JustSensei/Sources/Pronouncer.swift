import AVFoundation
import Foundation

/// Speaks Japanese aloud.
///
/// A vocabulary app that never makes a sound asks the learner to infer
/// pronunciation from kana they are still learning to read. Synthesis is not a
/// native speaker, but for a single word it is close enough to fix the pitch and
/// the mora count, which is what reading alone cannot give.
///
/// Offline and free: `AVSpeechSynthesizer` needs no network and no account.
@MainActor
public final class Pronouncer {
    public static let shared = Pronouncer()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    public var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Speaks `reading` when there is one, otherwise the word itself.
    ///
    /// The kana reading is preferred because the synthesiser has to guess at a
    /// kanji's reading exactly like the learner does — and for the words this app
    /// collects it guesses wrong often enough to matter. 「生」 alone is the
    /// standard example.
    public func speak(_ word: String, reading: String? = nil) {
        let text = (reading?.isEmpty == false ? reading : word) ?? word
        guard !text.isEmpty else { return }

        // Interrupts rather than queues: tapping a second word means the user is
        // done with the first.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.japaneseVoice
        // A single word at conversational speed is over before it registers.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }

    /// Reads a whole lyric line.
    ///
    /// Slower than a word, and for the opposite reason: a word is over before
    /// it registers, while a line has to be followed and written down as it
    /// goes. No reading is passed — a line's kanji are read from the words
    /// around them, which is the one place the synthesiser has more to work
    /// with than it does on a word alone.
    public func speakLine(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.japaneseVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.7
        synthesizer.speak(utterance)
    }

    /// Whether there is a Japanese voice to read with.
    ///
    /// False means the device would read a Japanese sentence in its own
    /// language, which is not something a listening exercise can be built on —
    /// the caller is expected to withhold the exercise rather than offer one
    /// that cannot be answered.
    public var canSpeakJapanese: Bool {
        Self.japaneseVoice?.language.hasPrefix("ja") == true
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Prefers an enhanced Japanese voice when the user has downloaded one.
    private static let japaneseVoice: AVSpeechSynthesisVoice? = {
        let japanese = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") }
        return japanese.first { $0.quality == .premium }
            ?? japanese.first { $0.quality == .enhanced }
            ?? japanese.first
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }()
}
