import JustCore
import JustDesign
import SwiftData
import SwiftUI

/// The home of the app: the groups by family, and what you were in the middle of.
///
/// This replaced search. The point of an idol app is not that you can find
/// anything — it is that the group you love is on the first screen, two taps
/// from a song.
struct GroupsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \StudySong.lastOpenedAt, order: .reverse) private var songs: [StudySong]

    @State private var showsSettings = false

    /// Shared through `AppModel` so constructing this screen stays cheap —
    /// see `AppModel.groupArtwork`.
    private var artworkStore: GroupArtworkStore { app.groupArtwork }

    /// As many columns as fit at card size. Two fixed columns gave an iPhone
    /// the right cards and an iPad two cards the size of a hand.
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 230), spacing: JustTheme.Space.snug),
    ]

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.groupsPath) {
            ZStack {
                JustBrandBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: JustTheme.Space.section) {
                        header
                        learningGuide
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
            // Bright list screen; the shared tiles read their ink from this.
            .environment(\.colorScheme, .light)
            .navigationDestination(for: IdolGroup.self) {
                GroupDetailScreen(group: $0, store: artworkStore)
            }
            // The gear sets the flag; this is what the flag opens. It went
            // missing in the idol-only restructure, and the button did nothing.
            .sheet(isPresented: $showsSettings) { SettingsScreen() }
            .task { await artworkStore.loadAll() }
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(JustTheme.Kawaii.accent)
                    .frame(width: 42, height: 42)
                    .background(JustTheme.Kitsch.bubblegum.opacity(0.5), in: .circle)
                    .kitschSticker(cornerRadius: 21, rim: 2.5, lift: 3)
                    // A turn of the cog each time it is pressed.
                    .symbolEffect(.rotate, value: showsSettings)
            }
            .buttonStyle(.kitschPress)
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
            .dismissibleGuide("home.start")
        .padding(.horizontal, JustTheme.Space.regular)
    }

    // MARK: - Continue

    private var continueShelf: some View {
        VStack(alignment: .leading, spacing: JustTheme.Space.snug) {
            Text("이어서 듣기").kawaiiSectionTitle()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: JustTheme.Space.snug) {
                    ForEach(Array(songs.prefix(10).enumerated()), id: \.element.id) { offset, song in
                        Button { app.open(song.track, in: songs.prefix(10).map(\.track)) } label: {
                            VStack(alignment: .leading, spacing: JustTheme.Space.tight) {
                                ArtworkTile(track: song.track, width: 148)
                                if song.studyProgress > 0 {
                                    StudyProgressBar(progress: song.studyProgress, width: 148)
                                }
                            }
                        }
                        .buttonStyle(.kitschPress)
                        .kitschEntrance(index: offset)
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
                    let order = IdolGroup.all.firstIndex(of: group) ?? 0
                    NavigationLink(value: group) {
                        GroupCard(group: group, artworkURL: artworkStore.artworkURL(for: group), order: order)
                    }
                    .buttonStyle(.kitschPress)
                    .kitschEntrance(index: order)
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
/// and a group the catalogue has no image for still looks like a group.
private struct GroupCard: View {
    let group: IdolGroup
    let artworkURL: URL?
    /// Place in the roster, so the foil sheens take turns instead of flashing
    /// across every card at once.
    let order: Int

    @State private var artwork = ArtworkLoader()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            JustTheme.Kawaii.gradient(hue: group.hue)

            if let image = artwork.image {
                // Fills the square and no more. A picture that is not square
                // otherwise widens the stack it sits in, and the card with it.
                Color.clear
                    .overlay {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
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
                    .kawaiiFont(18, weight: .black, relativeTo: .headline)
                    .foregroundStyle(.white)
                    .shadow(color: Color(hue: group.hue, saturation: 0.7, brightness: 0.45), radius: 0, x: 1.5, y: 2)
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
        // The foil catching the light, one card after another.
        // Six turns, then round again — with thirty cards, spacing them all
        // apart would leave the last ones waiting half a minute.
        .holoSheen(delay: Double(order % 6) * 0.9)
        .clipShape(.rect(cornerRadius: JustTheme.Radius.card))
        // Before the sticker, so the twinkle moves with the card when it is
        // pressed instead of hanging in the air above it.
        .overlay(alignment: .topTrailing) {
            Twinkle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .shadow(color: Color(hue: group.hue, saturation: 0.6, brightness: 0.8), radius: 0, x: 1, y: 1)
                .padding(10)
                .accessibilityHidden(true)
        }
        // A trading card: white rim, and a shadow printed in the group's own
        // colour.
        .kitschSticker(tint: Color(hue: group.hue, saturation: 0.55, brightness: 0.95), rim: 3.5, lift: 5)
        .animation(.easeInOut(duration: 0.25), value: artwork.image != nil)
        .task(id: artworkURL) { await artwork.load(artworkURL, trimmingLetterbox: true) }
    }
}
