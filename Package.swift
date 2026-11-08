// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PortfolioCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PortfolioCore", targets: ["PortfolioCore"])],
    targets: [
        .target(
            name: "PortfolioCore",
            path: "PortfolioAgent",
            exclude: [
                "LoginWelcomeView.swift", "NotificationCoordinator.swift",
                "LegalViews.swift", "CloudChatView.swift", "CloudProductViews.swift",
                "OverviewViews.swift", "DisciplineViews.swift", "CloudStore.swift",
                "CloudViews.swift", "AppStore.swift", "AskView.swift", "ContentView.swift",
                "DesignSystem.swift", "HoldingsViews.swift", "PortfolioAgentApp.swift",
                "ReviewViews.swift", "SettingsViews.swift", "Resources",
                "Assets.xcassets", "AppIcon.icon"
            ],
            sources: [
                "InstrumentSearch.swift", "Agreements.swift", "CloudChatModel.swift",
                "Models.swift", "MobileAPI.swift", "OverviewModels.swift"
            ]
        ),
        .testTarget(name: "PortfolioCoreTests", dependencies: ["PortfolioCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
