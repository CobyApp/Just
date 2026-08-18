import JustCore
import SwiftUI

public extension JLPTLevel {
    /// Green through red as the level gets harder; grey for out-of-syllabus.
    ///
    /// Ordered by hue rather than by arbitrary brand colours so a stacked bar
    /// reads as a difficulty gradient even without the labels.
    var tint: Color {
        switch self {
        case .n5: Color(red: 0.42, green: 0.78, blue: 0.55)
        case .n4: Color(red: 0.55, green: 0.76, blue: 0.45)
        case .n3: Color(red: 0.86, green: 0.74, blue: 0.40)
        case .n2: Color(red: 0.90, green: 0.58, blue: 0.36)
        case .n1: Color(red: 0.88, green: 0.44, blue: 0.44)
        case .beyond: JustTheme.Ink.tertiary
        }
    }
}
