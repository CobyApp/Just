import JustCore
import JustDesign
import SwiftData
import SwiftUI

/// The home of the app: seven groups, and what you were in the middle of.
///
/// This replaced search. The point of an idol app is not that you can find
/// anything — it is that the group you love is on the first screen, two taps
/// from a song.
struct GroupsScreen: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \StudySong.lastOpenedAt, order: .reverse) private var songs: [StudySong]

    @State private var showsSettings = false

    private let columns = [
        GridItem(.flexible(), spacing: JustTheme.Space.snug),
        GridItem(.flexible(), spacing: JustTheme.Space.snug),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                JustTheme.Surface.kawaii.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: JustTheme.Space.section) {
                        header
                        // Access has to be asked for somewhere, and this is the
                        // only screen that reaches Apple Music now. It used to
                        // live on the search screen; removing that took the
                        // permission prompt with it, and the app had no way to
                        // ask at all — which looks exactly like a group having
                        // no songs.
                        if !app.isAuthorized {
                            AppleMusicGate()
                                .environment(\.colorScheme, .light)
                                .padding(.top, JustTheme.Space.loose)
                        }
                        if !songs.isEmpty { continueShelf }
                        ForEach(IdolGroup.Label.allCases, id: \.self) { label in
                            groupSection(label)
                        }
                    }
                    .padding(.vertical, JustTheme.Space.regular)
                }
                .scrollIndicators(.hidden)
            }
            // The app is pinned to dark in its Info.plist, which the navigation
            // bar obeys — so on a bright screen the title and the toolbar
            // button were white on white. The bar is told otherwise.
            .navigationDestination(for: IdolGroup.self) { GroupDetailScreen(group: $0) }
        }
    }

    /// Drawn rather than left to the navigation bar.
    ///
    /// The app is pinned to dark in its Info.plist, and the bar obeys that even
    /// on a bright screen — the title and the settings button came out white on
    /// white. Drawing it here also lets it look like the rest of this screen.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("아이돌")
                .font(.just(34, weight: .heavy, relativeTo: .largeTitle))
                .foregroundStyle(JustTheme.Kawaii.ink)
            Spacer(minLength: 0)
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(JustTheme.Kawaii.ink)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.8), in: .circle)
            }
            .accessibilityLabel("설정")
        }
        .padding(.horizontal, JustTheme.Space.regular)
    }

    // MARK: - Continue

    private var continueShelf: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Text("이어서 공부하기").kawaiiSectionTitle()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                    ForEach(songs.prefix(10)) { song in
                        Button { app.open(song.track) } label: {
                            VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                                ArtworkTile(track: song.track, width: 148)
                                if song.studyProgress > 0 {
                                    StudyProgressBar(progress: song.studyProgress, width: 148)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, JustTheme.Space.regular)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Groups

    private func groupSection(_ label: IdolGroup.Label) -> some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Text(label.rawValue).kawaiiSectionTitle()
            LazyVGrid(columns: columns, spacing: JustTheme.Space.snug) {
                ForEach(IdolGroup.groups(in: label)) { group in
                    NavigationLink(value: group) { GroupCard(group: group) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, JustTheme.Space.regular)
        }
    }
}

/// One group, as a card you want to tap.
private struct GroupCard: View {
    let group: IdolGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.name)
                .font(.just(17, weight: .bold, relativeTo: .headline))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(group.readingKo)
                .font(JustTheme.Font.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .bottomLeading)
        .padding(JustTheme.Space.snug)
        .background(JustTheme.Kawaii.gradient(hue: group.hue), in: .rect(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.75))
                .padding(JustTheme.Space.snug)
        }
    }
}
