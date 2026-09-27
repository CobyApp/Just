import JustCore
import SwiftUI

public extension IdolGroup {
    /// The group's colour at a strength that holds up as text and as a
    /// selected tab on white — the card gradient's own tones are too pale for
    /// a yellow or mint group to read.
    var memberColor: Color {
        // Yellows and yellow-greens look bright at any brightness and carry
        // white text poorly; they are taken down further than the rest.
        let isYellowish = (0.08...0.24).contains(hue)
        return Color(hue: hue, saturation: 0.75, brightness: isYellowish ? 0.68 : 0.82)
    }
}

/// A gold crown sticker, for the favourite group's card.
public struct CrownSticker: View {
    private let size: CGFloat

    public init(size: CGFloat = 26) { self.size = size }

    public var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(
                LinearGradient(
                    colors: [JustTheme.Kitsch.lemon, Color(red: 1.0, green: 0.72, blue: 0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // A die-cut white edge, then the printed shadow.
            .shadow(color: .white, radius: 0, x: 1.5, y: 1.5)
            .shadow(color: .white, radius: 0, x: -1.5, y: -1.5)
            .shadow(color: .white, radius: 0, x: 1.5, y: -1.5)
            .shadow(color: .white, radius: 0, x: -1.5, y: 1.5)
            .shadow(color: JustTheme.Kitsch.stickerShadow.opacity(0.8), radius: 0, x: 2, y: 3)
            .rotationEffect(.degrees(-14))
            .accessibilityHidden(true)
    }
}
