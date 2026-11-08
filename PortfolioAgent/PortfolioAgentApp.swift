import SwiftUI
import CoreText

@main struct PortfolioAgentApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    @AppStorage("appearance") private var appearance = "system"
    @State private var store = AppStore()
    init() {
        for name in ["IBMPlexMono-Regular", "IBMPlexMono-Medium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environment(store).preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(Palette.blue)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}
