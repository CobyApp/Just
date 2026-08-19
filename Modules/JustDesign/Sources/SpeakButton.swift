import JustSensei
import SwiftUI

/// Speaks a Japanese word aloud when tapped.
public struct SpeakButton: View {
    private let word: String
    private let reading: String?
    private let size: CGFloat

    public init(word: String, reading: String? = nil, size: CGFloat = 30) {
        self.word = word
        self.reading = reading
        self.size = size
    }

    public var body: some View {
        Button {
            Pronouncer.shared.speak(word, reading: reading)
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(JustTheme.Ink.primary)
                .frame(width: size, height: size)
                .background(JustTheme.Surface.raised, in: .circle)
                .overlay {
                    Circle().strokeBorder(JustTheme.Ink.hairline, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("발음 듣기")
    }
}
