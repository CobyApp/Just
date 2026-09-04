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
    @State private var artworkStore = GroupArtworkStore()

    private let columns = [
        GridItem(.flexible(), spacing: JustTheme.Space.snug),
        GridItem(.flexible(), spacing: JustTheme.Space.snug),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                JustBrandBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: JustTheme.Space.section) {
                        header
                        learningGuide
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
                        // Below the last group. The grid is what this screen is
                        // for; the ad waits until it is over.
                        AdBanner(unitID: AdBanner.testUnitID)
                            .padding(.horizontal, JustTheme.Space.regular)
                    }
                    .padding(.vertical, JustTheme.Space.regular)
                }
                .scrollIndicators(.hidden)
            }
            // The app is pinned to dark in its Info.plist, which the navigation
            // bar obeys — so on a bright screen the title and the toolbar
            // button were white on white. The bar is told otherwise.
            // Bright list screen; the shared tiles read their ink from this.
            .environment(\.colorScheme, .light)
            .navigationDestination(for: IdolGroup.self) {
                GroupDetailScreen(group: $0, store: artworkStore)
            }
            .task(id: app.isAuthorized) {
                guard app.isAuthorized else { return }
                await artworkStore.loadAll()
            }
        }
    }

    /// Drawn rather than left to the navigation bar.
    ///
    /// The app is pinned to dark in its Info.plist, and the bar obeys that even
    /// on a bright screen — the title and the settings button came out white on
    /// white. Drawing it here also lets it look like the rest of this screen.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            JustScreenHeader("우타링", subtitle: "최애의 노래가 오늘의 일본어", showsMark: true)
            Spacer(minLength: 0)
            Button { showsSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(JustTheme.Kawaii.ink)
                    .frame(width: 40, height: 40)
                    .background(JustTheme.Surface.panel, in: .circle)
                    .overlay { Circle().strokeBorder(JustTheme.Surface.border, lineWidth: 1) }
            }
            .accessibilityLabel("설정")
        }
        .padding(.horizontal, JustTheme.Space.regular)
    }

    private var learningGuide: some View {
        JustFeatureGuide(
            "처음이라면 이렇게 시작하세요",
            detail: "노래를 듣다가 궁금한 가사만 눌러도 공부가 시작됩니다.",
            steps: [
                JustGuideStep("music.mic", title: "1. 그룹과 노래 고르기", detail: "좋아하는 그룹을 누르고 공부할 곡을 선택하세요."),
                JustGuideStep("text.quote", title: "2. 가사 한 줄 누르기", detail: "뜻·읽기·문법과 그 줄에 나온 단어를 보여드려요."),
                JustGuideStep("plus.circle.fill", title: "3. 단어장에 담기", detail: "+ 버튼으로 담으면 단어장과 연습 문제가 자동으로 만들어져요."),
            ]
        )
        .padding(.horizontal, JustTheme.Space.regular)
    }

    // MARK: - Continue

    private var continueShelf: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Text("이어서 듣기").kawaiiSectionTitle()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                    ForEach(songs.prefix(10)) { song in
                        Button { app.open(song.track, in: songs.prefix(10).map(\.track)) } label: {
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
                    NavigationLink(value: group) {
                        GroupCard(group: group, artworkURL: artworkStore.artworkURL(for: group))
                    }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, JustTheme.Space.regular)
        }
    }
}

/// One group, as a card you want to tap.
///
/// The group's own picture, with its colour laid over the bottom so the name
/// stays legible whatever the photo is doing there. Until the picture arrives
/// — or if it never does — the gradient alone is the card, so nothing flickers
/// and a group Apple Music has no image for still looks like a group.
private struct GroupCard: View {
    let group: IdolGroup
    let artworkURL: URL?

    @State private var artwork = ArtworkLoader()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            JustTheme.Kawaii.gradient(hue: group.hue)

            if let image = artwork.image {
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }

            // Colour over the lower half only. A full tint would hide the
            // photo; no tint would hide the name.
            LinearGradient(
                colors: [.clear, Color(hue: group.hue, saturation: 0.6, brightness: 0.55).opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.kawaii(17, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(group.readingKo)
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(JustTheme.Space.snug)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: JustTheme.Radius.card))
        .shadow(color: Color(hue: group.hue, saturation: 0.5, brightness: 0.7).opacity(0.25), radius: 10, y: 6)
        .animation(.easeInOut(duration: 0.25), value: artwork.image != nil)
        .task(id: artworkURL) { await artwork.load(artworkURL) }
    }
}
