import SwiftUI

/// Semantic colors resolve to the existing light/dark asset variants.
enum ShogunTheme {
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let ink = Color("Ink")
    static let muted = Color("MutedInk")
    static let accent = Color("AccentColor")
    static let raised = Color("RaisedSurface")
    static let boundary = Color("Boundary")
    static let primaryAction = Color("PrimaryAction")
    static let onPrimaryAction = Color("OnPrimaryAction")
    static let success = Color("Success")
    static let warning = Color("Warning")
    static let error = Color("Error")
    static let rating = Color("RatingInk")

    static let authPrimary = Color("AuthPrimary")
    static let onAccent = Color("OnAccent")
    static let authOnPrimary = Color("AuthOnPrimary")
    static let authSilverHighlight = Color("AuthSilverHighlight")

    enum Brand {
        static let compactWidth: CGFloat = 160
        static let authWidth: CGFloat = 300
        static let aspectRatio: CGFloat = 6
    }

    enum Auth {
        static let silver = LinearGradient(
            colors: [
                authSilverHighlight, Color("AuthSilverMidtone"), Color("AuthSilverSheen"),
                authPrimary,
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        static let contentWidth: CGFloat = 420
        static let fieldHeight: CGFloat = 52
        static let headerSpacing: CGFloat = 32
    }

    enum Spacing {
        static let tight: CGFloat = 4
        static let compact: CGFloat = 6
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let control: CGFloat = 12
        static let selector: CGFloat = 14
        static let regular: CGFloat = 16
        static let section: CGFloat = 18
        static let screen: CGFloat = 20
        static let large: CGFloat = 24
    }
    enum Radius {
        static let poster: CGFloat = 5
        static let control: CGFloat = 10
    }
    enum Size {
        static let tmdbLogoWidth: CGFloat = 110
        static let profileAvatar: CGFloat = 64
        static let touchTarget: CGFloat = 44
        static let ratingWidth: CGFloat = 36
        static let detailPosterWidth: CGFloat = 230
        static let searchPosterWidth: CGFloat = 64
        static let posterAspect: CGFloat = 2 / 3
    }
    enum Typography {
        static let authTitle = Font.title3.weight(.semibold)
        static let title = Font.title.bold()
        static let detailTitle = Font.largeTitle.bold()
        static let profileTitle = Font.title2.bold()
        static let headline = Font.headline
        static let body = Font.subheadline
        static let emphasizedBody = Font.subheadline.weight(.semibold)
        static let caption = Font.caption
        static let cardTitle = Font.caption.weight(.semibold)
        static let small = Font.caption2
        static let footnote = Font.footnote
        static let viewIcon = Font.title3
        static let actionIcon = Font.title2
        static let disclosure = Font.caption.weight(.semibold)
    }
    enum Poster {
        static let colors = (0..<6).map { Color("PosterTone\($0)") }
        static func titleFont(width: CGFloat) -> Font {
            .system(size: max(7, min(24, width * 0.09)), weight: .semibold)
        }
        static func inset(width: CGFloat) -> CGFloat { max(5, width * 0.08) }
        static let titleColor = Color("PosterInk")
    }
}
