import SwiftUI

internal enum ThemeColorModifiers {
    internal static func spec(from color: Color) -> ThemeColorSpec {
        ThemeResolver.color(from: color, traitCollection: .current)
    }

    internal static func spec(from semantic: ThemeColorSpec.SemanticColor) -> ThemeColorSpec {
        .semantic(semantic)
    }
}
