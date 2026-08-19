import JustCore
import JustDesign
import SwiftUI

/// What the user looks at between choosing a song and hearing it.
///
/// The wait is long — minutes, on a song the model has not seen — so this is
/// not a spinner. It says which song, how far along, and how much is left, and
/// it offers a way out that does not throw the finished lines away.
struct PreparingView: View {
    let track: Track
    let artwork: Image?
    let phase: SongSession.Phase
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: JustTheme.Space.loose) {
            Spacer(minLength: 0)

            ArtworkView(image: artwork, cornerRadius: JustTheme.Radius.card, seed: track.id)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)

            VStack(spacing: 4) {
                Text(track.title)
                    .font(JustTheme.Font.title)
                    .foregroundStyle(JustTheme.Ink.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(track.artist)
                    .font(JustTheme.Font.body)
                    .foregroundStyle(JustTheme.Ink.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            progress

            Spacer(minLength: 0)

            Button("중단", action: onCancel)
                .buttonStyle(.justSecondary)
        }
        .padding(JustTheme.Space.section)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var progress: some View {
        switch phase {
        case .loadingLyrics:
            VStack(spacing: JustTheme.Space.tight) {
                ProgressView()
                Text("가사를 찾는 중")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }

        case .analyzing(let done, let total, let remaining):
            VStack(spacing: JustTheme.Space.tight) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(JustTheme.Ink.primary)

                HStack {
                    Text("해석 중")
                    Spacer()
                    Text("\(done)/\(total)")
                        .monospacedDigit()
                }
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.secondary)

                if let remaining {
                    Text(Self.remainingText(remaining))
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
            }

        case .ready:
            EmptyView()
        }
    }

    /// Minutes once there is more than one, because a second-by-second
    /// countdown across ten minutes is worse company than a round number.
    static func remainingText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "약 \(max(total, 1))초 남음" }
        return "약 \(Int((Double(total) / 60).rounded()))분 남음"
    }
}
