import JustCore
import JustDesign
import JustSensei
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
    /// nil while there is nothing to skip — during the lyric fetch there is no
    /// partial result to go and read.
    let onSkip: (() -> Void)?
    /// nil unless the slow reading is what is being waited on. Offering the
    /// fast one during the lyric fetch would promise a speed-up of a step that
    /// is not the slow part.
    let onUseQuick: (() -> Void)?
    /// Answers the 「빠르게 / AI로」 question. nil except while it is asked.
    let onChoose: ((AnalysisDepth, Bool) -> Void)?

    @State private var rememberChoice = false

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

            if phase == .choosingDepth, let onChoose {
                choice(onChoose)
            } else {
                progress
            }

            Spacer(minLength: 0)

            if phase == .choosingDepth {
                // The question is the whole screen; the buttons below would
                // only compete with it. 「중단」 alone, and not in the card — a
                // card around one capsule drew a box with a pill inside it.
                Button("중단", action: onCancel)
                    .buttonStyle(.justSecondary)
            } else {
            VStack(spacing: JustTheme.Space.snug) {
                if let onSkip {
                    Button("지금 듣기", action: onSkip)
                        .buttonStyle(.justPrimary)
                    Text("남은 줄은 들으면서 이어서 해석합니다")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                }
                // Offered here because this screen is where the wait is
                // actually felt. A mode switch that lives only in settings is a
                // switch nobody finds while they are waiting for it.
                if let onUseQuick {
                    Button("빠른 번역으로 바꾸기", action: onUseQuick)
                        .buttonStyle(.justSecondary)
                    Text("남은 줄을 몇 초 안에 채웁니다. 다음 곡도 빠른 번역으로 열립니다.")
                        .font(JustTheme.Font.caption)
                        .foregroundStyle(JustTheme.Ink.tertiary)
                        .multilineTextAlignment(.center)
                }
                Button("중단", action: onCancel)
                    .buttonStyle(.justSecondary)
            }
            .justCard()
            }

            // Under the controls, so it never sits between the reader and the
            // button they are looking for.
            AdBanner(unitID: AdBanner.testUnitID)
        }
        .padding(JustTheme.Space.section)
        .frame(maxWidth: 420)
    }

    /// Which reading to make, asked in the reader's words.
    ///
    /// Two cards, not a picker: the difference is a decision about the next
    /// few minutes, and it deserves the sentence under each option that a
    /// picker row has no room for.
    private func choice(_ onChoose: @escaping (AnalysisDepth, Bool) -> Void) -> some View {
        VStack(spacing: JustTheme.Space.snug) {
            Text("어떻게 번역할까요?")
                .font(JustTheme.Font.title)
                .foregroundStyle(JustTheme.Ink.primary)

            choiceCard(
                title: "빠르게",
                detail: AnalysisDepth.quick.detail,
                symbol: "hare.fill"
            ) { onChoose(.quick, rememberChoice) }

            choiceCard(
                title: "AI로 정확하게",
                detail: AnalysisDepth.deep.detail,
                symbol: "sparkles"
            ) { onChoose(.deep, rememberChoice) }

            Toggle("다음에도 이걸로 열기", isOn: $rememberChoice)
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.secondary)
                .tint(JustTheme.Kawaii.accent)
                .padding(.top, JustTheme.Space.tight)
        }
    }

    private func choiceCard(
        title: String, detail: String, symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: JustTheme.Space.snug) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(JustTheme.Font.body.weight(.bold))
                    // The whole sentence. This is the one place the reader is
                    // told what the two choices mean, and an ellipsis after
                    // 「정확하…」 told them nothing.
                    Text(detail)
                        .font(JustTheme.Font.caption)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(JustTheme.Ink.primary)
            .padding(JustTheme.Space.regular)
            .frame(maxWidth: .infinity)
            .background(JustTheme.Surface.panel, in: .rect(cornerRadius: JustTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: JustTheme.Radius.card)
                    .strokeBorder(JustTheme.Surface.border, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var progress: some View {
        switch phase {
        case .choosingDepth:
            // The question replaces the bar; see `choice`.
            EmptyView()
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
                    .tint(JustTheme.Kawaii.accent)

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
