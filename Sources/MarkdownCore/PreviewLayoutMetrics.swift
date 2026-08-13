import Foundation

public enum PreviewLayoutMetrics {
    public static let horizontalPadding = 36.0
    public static let maximumContentWidth = 920.0

    public static func horizontalContentInset(for viewportWidth: Double) -> Double {
        max(horizontalPadding, (viewportWidth - maximumContentWidth) / 2)
    }
}
