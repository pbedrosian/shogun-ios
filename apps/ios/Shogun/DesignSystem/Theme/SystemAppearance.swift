import SwiftUI

/// Configure native navigation surfaces once at app startup.
enum ShogunSystemAppearance {
    static func configure() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "Canvas")
        appearance.shadowColor = UIColor(named: "Boundary")
        for layout in [
            appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.iconColor = UIColor(named: "MutedInk")
            layout.normal.titleTextAttributes = [
                .foregroundColor: UIColor(named: "MutedInk") ?? .secondaryLabel
            ]
            layout.selected.iconColor = UIColor(named: "AccentColor")
            layout.selected.titleTextAttributes = [
                .foregroundColor: UIColor(named: "AccentColor") ?? .tintColor
            ]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(named: "Canvas")
        navigation.titleTextAttributes = [.foregroundColor: UIColor(named: "Ink") ?? .label]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(named: "Ink") ?? .label]
        navigation.shadowColor = UIColor(named: "Boundary")
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
    }
}
