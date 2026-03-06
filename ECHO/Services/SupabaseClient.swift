//
//  SupabaseClient.swift
//  ECHO
//

import Foundation
import Supabase

/// Supabase client singleton. Set `SupabaseClient.initialize()` in app init with your project URL and anon key.
enum SupabaseClient {
    private(set) static var shared: Supabase.SupabaseClient?
    
    /// Call once at app launch (e.g. from ECHOApp). Use your Supabase project URL and anon key.
    static func initialize(url: URL, anonKey: String) {
        shared = Supabase.SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: Supabase.SupabaseClientOptions(
                auth: Supabase.SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
    
    /// Use when Supabase is not configured (e.g. missing keys) — app falls back to in-memory mock.
    static var isConfigured: Bool { shared != nil }
}
