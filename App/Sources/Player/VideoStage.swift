import JustMusic
import SwiftUI
import UIKit

/// The song's video, where the artwork used to be.
///
/// The web view belongs to the player and lives as long as the app; this only
/// gives it a place on screen. Moving it here from wherever it was keeps
/// playback going through a relayout, and taking it off screen is what pauses
/// it — see `MusicPlayerController`.
struct VideoStage: UIViewRepresentable {
    let player: MusicPlayerController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        let video = player.videoView
        guard video.superview !== container else { return }
        video.removeFromSuperview()
        video.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(video)
        NSLayoutConstraint.activate([
            video.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            video.topAnchor.constraint(equalTo: container.topAnchor),
            video.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
