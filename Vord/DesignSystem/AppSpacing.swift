import CoreGraphics

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    static let s = sm
    static let m = md
    static let l = lg

    /// Shared inset from the white card edge on every page.
    static let page: CGFloat = 40
    static let railWidth: CGFloat = 156
    static let controlHeight: CGFloat = 36
    static let measure: CGFloat = 1000
    static let library: CGFloat = 1000
    static let settings: CGFloat = 900
    static let prose: CGFloat = 520
    static let sidebar: CGFloat = 292
    /// Extra trailing inset so the expanded-window chrome button stays clear of content.
    static let chromeClearance: CGFloat = 32
}
