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
                    Haptics.prepareAll()
                    await PushManager.shared.requestPermission()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in
                    // Reconnect socket if it dropped while in background
                    if !appState.isConnected {
                        await appState.connect()
                    }
                    // Always refresh sessions to pick up messages missed while backgrounded
                    await appState.refreshSessions()
                    // Delay briefly then restart Live Activities
                    try? await Task.sleep(nanoseconds: 800_000_000)
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
