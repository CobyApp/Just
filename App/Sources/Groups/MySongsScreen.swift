import JustCore
import JustDesign
import SwiftData
import SwiftUI

/// Every song you have opened, newest first.
///
/// This is the playlist the app builds for you by being used: a song enters it
/// the moment it is opened and carries its study progress with it. Second tab,
/// because after the first day it is where most sessions start — the group
/// grid is for finding a new song, this is for going back to one.
struct MySongsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \StudySong.lastOpenedAt, order: .reverse) private var songs: [StudySong]

    var body: some View {
        NavigationStack {
            ZStack {
                JustBrandBackground()
                if songs.isEmpty {
                    JustEmptyState(
                        icon: "music.note.list",
                        title: "아직 연 곡이 없습니다",
                        message: "그룹에서 곡을 열면 여기에 모입니다. 해석과 진도가 함께 남습니다.",
                        actionTitle: "그룹 보러 가기",
                        action: { app.tab = .groups }
                    )
                } else {
                    list
                }
            }
            .environment(\.colorScheme, .light)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
                HStack(alignment: .firstTextBaseline) {
                    JustScreenHeader("내 노래", subtitle: "다시 듣고 싶은 가사 공부")
                    Spacer()
                    Text("\(songs.count)곡")
                        .font(JustTheme.Font.caption.monospacedDigit())
                        .foregroundStyle(JustTheme.Kawaii.inkSoft)
                }
                .padding(.horizontal, JustTheme.Space.regular)

                JustActionHint("최근에 열었던 곡과 공부 진도가 자동으로 저장됩니다. 곡을 누르면 이어서 공부해요.", symbol: "clock.arrow.circlepath")
                    .padding(.horizontal, JustTheme.Space.regular)

                LazyVStack(spacing: JustTheme.Space.tight) {
                    ForEach(songs) { song in
                        Button { app.open(song.track, in: songs.map(\.track)) } label: { row(song) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("목록에서 빼기", systemImage: "trash", role: .destructive) {
                                    remove(song)
                                }
                            }
                    }
                }
                .padding(.horizontal, JustTheme.Space.regular)

                AdBanner(unitID: AdBanner.testUnitID)
                    .padding(.top, JustTheme.Space.regular)
            }
            .padding(.vertical, JustTheme.Space.regular)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ song: StudySong) -> some View {
        SongRow(track: song.track, progress: song.studyProgress, action: "이어서")
    }

    /// Taking a song out of the list takes its record with it — the lyrics,
    /// the analysis, the progress. Saved words stay: they are the reader's,
    /// not the song's.
    private func remove(_ song: StudySong) {
        context.delete(song)
    }
}
