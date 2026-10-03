import SwiftUI

struct AppLayout: Equatable {
    var contentSize = CGSize(width: 1000, height: 740)
    var pagePadding: CGFloat { contentSize.width < 780 ? 24 : 40 }
    var usableWidth: CGFloat { max(0, contentSize.width - pagePadding * 2) }
    var usesColumns: Bool { usableWidth >= 760 }
    var compactHeight: Bool { contentSize.height < 650 }
    var studyHeight: CGFloat { min(280, max(150, contentSize.height - 350)) }

    static func railWidth(windowWidth: CGFloat) -> CGFloat { windowWidth < 960 ? 56 : 144 }
}

private struct AppLayoutKey: EnvironmentKey {
    static let defaultValue = AppLayout()
}

extension EnvironmentValues {
    var vordLayout: AppLayout {
        get { self[AppLayoutKey.self] }
        set { self[AppLayoutKey.self] = newValue }
    }
}
