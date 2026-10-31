import UIKit

/// 全局视觉常量。颜色一律用语义色,accent 走 Asset Catalog(Any/Dark 变体)。
enum Theme {
    static var accent: UIColor {
        UIColor(named: "Accent") ?? .systemBlue
    }

    static let cardCornerRadius: CGFloat = 10
    static let contentInset: CGFloat = 16
}
