import SwiftUI

/// A ring that fills toward a daily goal, with the streak in the middle.
///
/// The streak is the number a returning user looks for first, so it gets the
/// one piece of saturated colour in the app. The ring around it answers the
/// other question — how much of today is done — without a second widget.
public struct StreakRing: View {
    private let streak: Int
    private let progress: Double
    private let diameter: CGFloat

    @State private var animatedProgress: Double = 0

    public init(streak: Int, progress: Double, diameter: CGFloat = 132) {
        self.streak = streak
        self.progress = min(max(progress, 0), 1)
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(JustTheme.Surface.raised, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    JustTheme.Accent.angular,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                // Start at the top rather than at 3 o'clock, which is where a
                // progress ring is expected to begin.
                .rotationEffect(.degrees(-90))
                .shadow(color: JustTheme.Accent.end.opacity(0.5), radius: 8)

            VStack(spacing: 0) {
                Text("\(streak)")
                    .font(.system(size: diameter * 0.3, weight: .bold).monospacedDigit())
                    .foregroundStyle(JustTheme.Ink.primary)
                Text("일 연속")
                    .font(JustTheme.Font.caption)
                    .foregroundStyle(JustTheme.Ink.tertiary)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { animatedProgress = progress }
        }
        .onChange(of: progress) { _, new in
            withAnimation(.easeOut(duration: 0.5)) { animatedProgress = new }
        }
    }

    private var lineWidth: CGFloat { diameter * 0.09 }
}
