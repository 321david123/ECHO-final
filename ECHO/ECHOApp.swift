//
//  ECHOApp.swift
//  ECHO — Yik Yak for Mexican universities
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct ECHOApp: App {
    @UIApplicationDelegateAdaptor(ECHOAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    
    private var showContentView: Bool {
        if appState.requiresReauthAfterSignOut { return false }
        guard appState.hasCompletedOnboarding else { return false }
        if appState.useSupabase {
            return appState.hasAttemptedRestore && appState.verifiedCampus != nil
        }
        return true
    }
    
    private var showLoading: Bool {
        appState.hasCompletedOnboarding && appState.useSupabase && !appState.hasAttemptedRestore
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if showLoading {
                    ZStack {
                        Color.echoBackground.ignoresSafeArea()
                        ProgressView()
                            .tint(Color.echoGreen)
                    }
                    .environmentObject(appState)
                } else if showContentView {
                    ContentView()
                        .environmentObject(appState)
                } else {
                    OnboardingView()
                        .environmentObject(appState)
                }
            }
            .id("\(appState.requiresReauthAfterSignOut)-\(appState.hasCompletedOnboarding)-\(appState.verifiedCampus?.id ?? "")")
            .onOpenURL { url in
                appState.handleAuthCallbackURL(url)
            }
        }
    }
}

// MARK: - App delegate for push (APNs token). In same file so it's always in the target.
final class ECHOAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let didRegisterDeviceTokenNotification = Notification.Name("ECHO_DidRegisterDeviceToken")
    private static let tokenKey = "ECHO_APNs_device_token"
    
    static func clearStoredToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
    
    static var storedDeviceToken: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(tokenString, forKey: Self.tokenKey)
        NotificationCenter.default.post(name: Self.didRegisterDeviceTokenNotification, object: nil)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }
}
