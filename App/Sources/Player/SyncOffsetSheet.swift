import JustCore
import JustDesign
import JustMusic
import SwiftUI

/// Lines up a lyric sheet that runs early or late against the recording.
///
/// Two ways in, because they fail in opposite directions. Tapping the line you
/// can hear is one gesture and lands within a reaction time; nudging is slow but
/// exact. Doing the coarse move by ear and the last tenth by eye is faster than
/// either alone.
struct SyncOffsetSheet: View {
    @Bindable var session: SongSession
    let player: MusicPlayerController

    @Environment(\.dismiss) private var dismiss

    /// How far around the app's current guess to offer lines.
    ///
    /// Enough to cover the whole correctable range — five seconds at a few
    /// seconds a line — without turning the sheet into the lyrics screen again.
    private static let neighbourhood = 3

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.base.ignoresSafeArea()
                VStack(spacing: JustTheme.Space.loose) {
                    reading
                    dial
                    Divider().overlay(JustTheme.Ink.hairline)
                    byEar
                    Spacer(minLength: 0)
                }
                .padding(JustTheme.Space.regular)
            }
            .navigationTitle("가사 싱크 조절")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화") { session.lyricsOffset = 0 }
                        .disabled(session.lyricsOffset == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    // MARK: - Current value

    private var reading: some View {
        VStack(spacing: JustTheme.Space.tight) {
            Text(Self.label(for: session.lyricsOffset))
                .font(.just(40, weight: .semibold, relativeTo: .largeTitle).monospacedDigit())
                .foregroundStyle(JustTheme.Ink.primary)
                .contentTransition(.numericText())
            Text(Self.explanation(for: session.lyricsOffset))
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, JustTheme.Space.regular)
    }

    static func label(for offset: TimeInterval) -> String {
        offset == 0 ? "맞음" : String(format: "%+.1f초", offset)
    }

    /// Says which way it moved in the reader's own terms — the sign alone does
    /// not tell anyone whether the words come sooner or later.
    static func explanation(for offset: TimeInterval) -> String {
        if offset == 0 { return "가사가 노래와 맞습니다." }
        return offset > 0
            ? "가사를 \(String(format: "%.1f", offset))초 늦춥니다. 가사가 노래보다 앞서 갈 때."
            : "가사를 \(String(format: "%.1f", -offset))초 당깁니다. 가사가 노래보다 늦게 올 때."
    }

    // MARK: - By hand

    private var dial: some View {
        HStack(spacing: JustTheme.Space.snug) {
            step(-0.5)
            step(-0.1)
            step(0.1)
            step(0.5)
        }
    }

    private func step(_ delta: TimeInterval) -> some View {
        Button(String(format: "%+.1f", delta)) {
            session.lyricsOffset = LyricSync.stepped(session.lyricsOffset, by: delta)
            Haptics.tick()
        }
        .buttonStyle(.justSecondary)
        .disabled(atLimit(delta))
        .frame(maxWidth: .infinity)
    }

    private func atLimit(_ delta: TimeInterval) -> Bool {
        LyricSync.stepped(session.lyricsOffset, by: delta) == session.lyricsOffset
    }

    // MARK: - By ear

    private var byEar: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Text("지금 들리는 줄을 누르세요")
                .font(JustTheme.Font.body.weight(.semibold))
                .foregroundStyle(JustTheme.Ink.primary)
            Text("앱이 짚고 있는 줄이 아니라, 실제로 노래하고 있는 줄입니다.")
                .font(JustTheme.Font.caption)
                .foregroundStyle(JustTheme.Ink.tertiary)

            if candidates.isEmpty {
                Text("재생을 시작하면 이 곡의 줄이 여기에 나옵니다.")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            } else {
                ForEach(candidates) { line in
                    Button { calibrate(to: line) } label: {
                        HStack(spacing: JustTheme.Space.snug) {
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(JustTheme.Font.body)
                                .foregroundStyle(
                                    line.id == guess ? JustTheme.Ink.primary : JustTheme.Ink.secondary
                                )
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if line.id == guess {
                                Text("앱의 짚음")
                                    .font(JustTheme.Font.caption)
                                    .foregroundStyle(JustTheme.Ink.tertiary)
                            }
                        }
                        .padding(.vertical, JustTheme.Space.tight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The line the app currently believes is playing.
    private var guess: Int? {
        session.activeLine(at: player.position)
    }

    /// Lines around the app's guess, which is where the right answer must be:
    /// the correction is capped at five seconds and lines run a few seconds
    /// apart, so the line actually being sung is a handful either side.
    private var candidates: [LyricLine] {
        guard let lines = session.lyrics?.lines, !lines.isEmpty else { return [] }
        let centre = lines.firstIndex { $0.id == guess } ?? 0
        let lower = max(0, centre - Self.neighbourhood)
        let upper = min(lines.count - 1, centre + Self.neighbourhood)
        return Array(lines[lower...upper])
    }

    private func calibrate(to line: LyricLine) {
        guard let songTime = player.position.songTime, let lineTime = line.time else { return }
        session.lyricsOffset = LyricSync.calibrated(songTime: songTime, lineTime: lineTime)
        Haptics.tick()
    }
}
