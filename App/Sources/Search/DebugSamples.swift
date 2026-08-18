#if DEBUG
import JustCore

/// Fixed songs that open without touching the Apple Music catalog.
///
/// MusicKit needs a real device with a signed-in account, so on the Simulator
/// there is otherwise no way to reach the lyric view at all — which is exactly
/// where the furigana, the analysis prompt and the dictionary cross-check get
/// iterated on. Playback fails here (the ids are not catalog ids), but lyrics,
/// analysis, saving and review all run for real.
enum DebugSamples {
    static let all: [Track] = [
        Track(
            id: "debug.lemon",
            title: "Lemon",
            artist: "米津玄師",
            album: "BOOTLEG",
            duration: 256
        ),
        Track(
            id: "debug.yorunikakeru",
            title: "夜に駆ける",
            artist: "YOASOBI",
            album: "THE BOOK",
            duration: 261
        ),
        Track(
            id: "debug.pretender",
            title: "Pretender",
            artist: "Official髭男dism",
            album: "Traveler",
            duration: 325
        ),
    ]
}
#endif
