import SwiftUI

@main
struct CodeLightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await PushManager.shared.requestPermission()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Delay briefly to ensure app is fully visible before starting Live Activities
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                    appState.startLiveActivitiesForActiveSessions()
                }
            }
        }
    }
}

/// AppDelegate for push notification registration callbacks.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}
