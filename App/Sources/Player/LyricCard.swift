import JustCore
import JustDesign
import JustSensei
import SwiftUI

/// One lyric line as a picture to post: the line with its readings, what it
/// means, and where it is from, dressed like a sticker on a goods-shop page.
///
/// Fans share a line that stuck with them; a card that shows the reading and
/// the meaning is also the study note. One line only — a short quote, never
/// the lyrics.
struct LyricCard: View {
    let line: String
    let translation: String?
    let title: String
    let artist: String
    /// The group's colour, when the song is by one of the roster's groups.
    let tint: Color

    var body: some View {
        ZStack {
            JustBrandBackground()

            VStack(alignment: .leading, spacing: 18) {
                RubyText(
                    segments: Furigana.segments(forLine: line),
                    font: .just(30, weight: .bold, relativeTo: .title1),
                    rubyFont: .just(13, weight: .semibold, relativeTo: .caption2),
                    color: JustTheme.Kawaii.ink,
                    rubyColor: tint,
                    rubyHeight: 16
                )
                .fixedSize(horizontal: false, vertical: true)

                if let translation, !translation.isEmpty {
                    Text(translation)
                        .font(.just(18, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(JustTheme.Kawaii.inkSoft)
                        .kitschHighlight(JustTheme.Kitsch.lemon)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .black))
                    Text("\(title) — \(artist)")
                        .font(.just(13, weight: .bold, relativeTo: .caption1))
                        .lineLimit(2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(tint, in: .capsule)
                .overlay { Capsule().strokeBorder(.white, lineWidth: 2) }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(tint.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .padding(6)
            }
            .kitschSticker(cornerRadius: 28, tint: tint, rim: 4, lift: 6)
            .overlay(alignment: .top) { WashiTape(JustTheme.Kitsch.mint, angle: -5).offset(y: -10) }
            .overlay(alignment: .topTrailing) {
                SparkleCluster(tint: tint).offset(x: 6, y: -16)
            }
            .padding(.horizontal, 28)

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    RingRingMark(size: 26)
                    Text("링링 · 최애의 노래로 배우는 일본어")
                        .font(.just(12, weight: .bold, relativeTo: .caption1))
                        .foregroundStyle(JustTheme.Kawaii.inkSoft)
                }
                .padding(.bottom, 26)
            }
        }
        .frame(width: 360, height: 450)
        .environment(\.colorScheme, .light)
    }
}

/// The card, previewed before it is shared.
struct LyricCardSheet: View {
    let card: LyricCard

    @Environment(\.dismiss) private var dismiss
    @State private var image: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: JustTheme.Space.loose) {
                Group {
                    if let image {
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: JustTheme.Radius.card))
                            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                    } else {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(maxHeight: .infinity)

                if let image {
                    ShareLink(
                        item: image,
                        preview: SharePreview("가사 카드", image: image)
                    ) {
                        Label("공유하기", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.justPrimary)
                }
            }
            .padding(JustTheme.Space.regular)
            .background(JustBrandBackground())
            .navigationTitle("가사 카드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .task { render() }
    }

    /// Drawn once, at three times the card's size: 1080×1350, the portrait
    /// shape feeds crop to least.
    private func render() {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let rendered = renderer.uiImage {
            image = Image(uiImage: rendered)
        }
    }
}
