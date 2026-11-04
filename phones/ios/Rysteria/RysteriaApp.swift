import SwiftUI

@main
struct RysteriaApp: App {
    var body: some Scene {
        WindowGroup {
            WebScreen()
                .ignoresSafeArea()
                .background(Color.black)
                .statusBarHidden(true)
                .hideSystemOverlays()
        }
    }
}

extension View {
    /// hides the home indicator and other system overlays; the call exists from iOS 16, the app still runs on 15
    @ViewBuilder func hideSystemOverlays() -> some View {
        if #available(iOS 16.0, *) {
            self.persistentSystemOverlays(.hidden)
        } else {
            self
        }
    }
}
