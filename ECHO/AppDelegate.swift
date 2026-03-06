//
//  AppDelegate.swift
//  ECHO
//

import UIKit
import UserNotifications

/// Captures APNs device token and stores it for AppState to upload to Supabase.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let didRegisterDeviceTokenNotification = Notification.Name("ECHO_DidRegisterDeviceToken")
    private static let tokenKey = "ECHO_APNs_device_token"
    
    /// Call from AppState when the token has been uploaded; removes from UserDefaults.
    static func clearStoredToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
    
    /// Token string (hex) if we have one waiting to be uploaded.
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
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // e.g. simulator has no push; user denied permission
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge, .list]
    }
}
