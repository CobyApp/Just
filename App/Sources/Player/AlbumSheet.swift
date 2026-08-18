import JustCore
import JustDesign
import JustMusic
import SwiftUI

/// The record a song came from: cover, year, and the full running order.
///
/// Reachable by tapping the album name on the player. Studying a whole album
/// is a natural unit — the same writer, the same register, often the same
/// vocabulary — so getting from one song to its siblings should be one tap.
struct AlbumSheet: View {
    let track: Track

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var album: AlbumDetail?
    @State private var artwork = ArtworkLoader()
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if let album {
                    ArtworkBackground(palette: artwork.palette)
                    content(album)
                } else {
                    JustTheme.Surface.base.ignoresSafeArea()
                    if let failure {
                        ContentUnavailableView {
                            Label("앨범을 불러오지 못했습니다", systemImage: "square.stack")
                        } description: {
                            Text(failure)
                        }
                    } else {
                        VStack(spacing: JustTheme.Space.loose) {
                            Skeleton(cornerRadius: JustTheme.Radius.card)
                                .frame(width: 260, height: 260)
                            Skeleton().frame(width: 180, height: 20)
                            VStack(spacing: JustTheme.Space.snug) {
                                ForEach(0..<6, id: \.self) { _ in
                                    Skeleton().frame(height: 16)
                                }
                            }
                            .padding(.horizontal, JustTheme.Space.loose)
                        }
                        .padding(JustTheme.Space.regular)
                    }
                }
            }
            .navigationTitle(album?.title ?? "앨범")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .task {
            do {
                let detail = try await app.music.album(forTrackID: track.id)
                album = detail
                await artwork.load(detail.artworkURL)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func content(_ album: AlbumDetail) -> some View {
        ScrollView {
            VStack(spacing: JustTheme.Space.loose) {
                VStack(spacing: JustTheme.Space.snug) {
                    ArtworkView(
                        image: artwork.image,
                        cornerRadius: JustTheme.Radius.card,
                        seed: album.id
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 260)
                    .shadow(color: .black.opacity(0.45), radius: 26, y: 12)

                    VStack(spacing: 4) {
                        Text(album.title)
                            .font(JustTheme.Font.title)
                            .foregroundStyle(JustTheme.Ink.primary)
                            .multilineTextAlignment(.center)
                        Text(album.artist)
                            .font(JustTheme.Font.body)
                            .foregroundStyle(JustTheme.Ink.secondary)
                        Text(metadata(album))
                            .font(JustTheme.Font.caption)
                            .foregroundStyle(JustTheme.Ink.tertiary)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, item in
                        Button {
                            app.open(item)
                            dismiss()
                        } label: {
                            trackRow(index: index + 1, track: item)
                        }
                        .buttonStyle(.plain)

                        if item.id != album.tracks.last?.id {
                            Divider().overlay(JustTheme.Ink.hairline)
                        }
                    }
                }
                .justCard()
            }
            .padding(JustTheme.Space.regular)
        }
        .scrollIndicators(.hidden)
    }

    private func trackRow(index: Int, track item: Track) -> some View {
        HStack(spacing: JustTheme.Space.snug) {
            Text("\(index)")
                .font(JustTheme.Font.caption.monospacedDigit())
                .foregroundStyle(JustTheme.Ink.tertiary)
                .frame(width: 22, alignment: .trailing)

            Text(item.title)
                .font(JustTheme.Font.body)
                // The song the sheet was opened from is highlighted so the
                // user keeps their place in the running order.
                .foregroundStyle(
                    item.id == track.id ? JustTheme.Ink.primary : JustTheme.Ink.secondary
                )
                .lineLimit(1)

            Spacer(minLength: JustTheme.Space.tight)

            if item.duration > 0 {
                Text(item.duration.clockString)
                    .font(JustTheme.Font.caption.monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func metadata(_ album: AlbumDetail) -> String {
        [album.genre, album.releaseYear, "\(album.tracks.count)곡"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
