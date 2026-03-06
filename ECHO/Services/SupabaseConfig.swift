//
//  SupabaseConfig.swift
//  ECHO
//
//  Add your Supabase URL and anon key here for development, or use a plist/env in production.
//

import Foundation

enum SupabaseConfig {
    /// Your Supabase project URL (e.g. https://xxxx.supabase.co)
    static let urlString: String? = {
        ProcessInfo.processInfo.environment["ECHO_SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "ECHO_SUPABASE_URL") as? String
    }()
    
    /// Your Supabase anon/public key
    static let anonKey: String? = {
        ProcessInfo.processInfo.environment["ECHO_SUPABASE_ANON_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "ECHO_SUPABASE_ANON_KEY") as? String
    }()
    
    static var isConfigured: Bool {
        guard let s = urlString, let k = anonKey,
              !s.isEmpty, !k.isEmpty,
              let url = URL(string: s) else { return false }
        return url.scheme == "https"
    }
    
    /// Reviewer / dev login: this email + code 123456 skips real OTP and enters with mock data (any campus). No email is sent.
    static let reviewerEmail: String? = {
        ProcessInfo.processInfo.environment["ECHO_REVIEWER_EMAIL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "ECHO_REVIEWER_EMAIL") as? String
            ?? "review@echoiosone.com"
    }()
    
    static let reviewerCode = "123456"
}
