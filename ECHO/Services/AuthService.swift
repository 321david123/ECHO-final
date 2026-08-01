//
//  AuthService.swift
//  ECHO
//

import Foundation
import Supabase

/// Handles auth: WorkOS Magic Auth (6-digit OTP) for email, then Supabase session for DB.
final class AuthService: ObservableObject {
    private var client: Supabase.SupabaseClient? { SupabaseClient.shared }
    
    /// Call from async context only.
    func getSession() async throws -> Session? {
        try await client?.auth.session
    }
    
    /// Call from async context only.
    func getCurrentUserId() async -> UUID? {
        (try? await getSession())?.user.id
    }

    /// When the current account was created (used to gate the referral claim prompt to fresh signups).
    func getCurrentUserCreatedAt() async -> Date? {
        (try? await getSession())?.user.createdAt
    }
    
    /// Sign in anonymously (no email, no OTP). Call createProfile(uid, campusId) after.
    func signInAnonymously() async throws {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        _ = try await client.auth.signInAnonymously()
    }
    
    /// Sign in with email + password (used for persistent reviewer account).
    func signInWithPassword(email: String, password: String) async throws {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        _ = try await client.auth.signIn(email: email, password: password)
    }
    
    /// Create account with email + password (used for persistent reviewer account).
    func signUpWithPassword(email: String, password: String) async throws {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        _ = try await client.auth.signUp(email: email, password: password)
    }
    
    /// Send 6-digit OTP via WorkOS (Edge Function workos-send-otp). Caller must validate email domain for campus.
    func sendOTP(email: String, campusId: String) async throws {
        guard let baseURL = SupabaseConfig.urlString, let anonKey = SupabaseConfig.anonKey else {
            throw EchoError.supabaseNotConfigured
        }
        let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/functions/v1/workos-send-otp")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(WorkOSSendOTPBody(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            campus_id: campusId
        ))
        let (data, res) = try await URLSession.shared.data(for: req)
        try checkFunctionError(data: data, response: res, fallback: "Error al enviar el código.")
    }
    
    /// Verify 6-digit WorkOS code, open magic link in browser, set Supabase session from callback. Call createProfile(campusId) after.
    func verifyOTP(email: String, code: String, campusId: String) async throws {
        guard let baseURL = SupabaseConfig.urlString, let anonKey = SupabaseConfig.anonKey else {
            throw EchoError.supabaseNotConfigured
        }
        let url = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/functions/v1/workos-verify-otp")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(WorkOSVerifyOTPBody(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            campus_id: campusId
        ))
        let (data, res) = try await URLSession.shared.data(for: req)
        try checkFunctionError(data: data, response: res, fallback: "Código inválido o expirado.")
        let decoded = try JSONDecoder().decode(WorkOSVerifyOTPResponse.self, from: data)
        guard let accessToken = decoded.access_token, let refreshToken = decoded.refresh_token else {
            throw EchoError.decodingFailed
        }
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
    }
    
    /// Set Supabase session from echo://auth/callback URL (fragment: access_token, refresh_token; query: campus_id). Used when app is opened via link.
    func setSessionFromCallbackURL(_ url: URL) async throws {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        guard let fragment = url.fragment, !fragment.isEmpty else {
            throw EchoError.functionError("URL de callback inválida.")
        }
        let params = parseFragment(fragment)
        guard let accessToken = params["access_token"], let refreshToken = params["refresh_token"] else {
            throw EchoError.functionError("Faltan tokens en la URL.")
        }
        try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
    }

    private func parseFragment(_ fragment: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in fragment.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, let key = pair[0].removingPercentEncoding, let value = pair[1].removingPercentEncoding {
                result[key] = value
            }
        }
        return result
    }
    
    private func checkFunctionError(data: Data, response: URLResponse, fallback: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 200 && http.statusCode < 300 { return }
        if let err = try? JSONDecoder().decode(FunctionErrorBody.self, from: data), !err.error.isEmpty {
            if err.error == "invalid_email_domain" { throw EchoError.invalidEmailDomain }
            if err.error == "invalid_code" { throw EchoError.invalidOrExpiredCode }
            throw EchoError.functionError(err.error)
        }
        throw EchoError.functionError(fallback)
    }
    
    /// Create or update profile with campus_id (call after sign up or when changing campus).
    func createProfile(userId: UUID, campusId: String) async throws {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let profile = ProfileUpsert(id: userId, campusId: campusId)
        try await client
            .from("profiles")
            .upsert(profile, onConflict: "id")
            .execute()
    }
    
    /// Update the current user's display name, emoji, and/or accent color. Pass nil to clear any field.
    func updateProfileDisplay(displayName: String?, emoji: String?, accentColor: String?) async throws {
        guard let client = client, let uid = await getCurrentUserId() else { throw EchoError.notAuthenticated }
        let payload = ProfileDisplayUpdate(displayName: displayName, emoji: emoji, accentColor: accentColor, updatedAt: Date())
        try await client
            .from("profiles")
            .update(payload)
            .eq("id", value: uid.uuidString)
            .execute()
    }
    
    /// Fetch profile for current user (campus_id).
    func fetchProfile() async throws -> ProfileRow? {
        guard let client = client, let uid = await getCurrentUserId() else { return nil }
        let response: [ProfileRow] = try await client
            .from("profiles")
            .select()
            .eq("id", value: uid.uuidString)
            .execute()
            .value
        return response.first
    }
    
    /// Sign out.
    func signOut() async throws {
        try await client?.auth.signOut()
    }
    
    /// Listen for auth state changes (e.g. session restored).
    func onAuthStateChange(_ callback: @escaping (AuthChangeEvent, Session?) -> Void) {
        Task {
            await client?.auth.onAuthStateChange { event, session in
                DispatchQueue.main.async {
                    callback(event, session)
                }
            }
        }
    }
}

private struct WorkOSSendOTPBody: Encodable {
    let email: String
    let campus_id: String
}

private struct WorkOSVerifyOTPBody: Encodable {
    let email: String
    let code: String
    let campus_id: String
}

private struct WorkOSVerifyOTPResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let campus_id: String?
}

private struct FunctionErrorBody: Decodable {
    let error: String
}

/// Profile row from Supabase.
struct ProfileRow: Codable {
    let id: UUID
    let campusId: String
    let displayName: String?
    let emoji: String?
    let accentColor: String?
    let createdAtString: String?
    let updatedAtString: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case campusId = "campus_id"
        case displayName = "display_name"
        case emoji
        case accentColor = "accent_color"
        case createdAtString = "created_at"
        case updatedAtString = "updated_at"
    }
    
    var createdAt: Date { createdAtString.flatMap { Self.parse($0) } ?? Date() }
    var updatedAt: Date { updatedAtString.flatMap { Self.parse($0) } ?? Date() }
    private static func parse(_ s: String) -> Date? {
        let withFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
        let plain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
        return withFrac.date(from: s) ?? plain.date(from: s)
    }
}

private struct ProfileUpsert: Encodable {
    let id: UUID
    let campusId: String
    let updatedAt: Date = Date()
    enum CodingKeys: String, CodingKey {
        case id
        case campusId = "campus_id"
        case updatedAt = "updated_at"
    }
}

private struct ProfileDisplayUpdate: Encodable {
    let displayName: String?
    let emoji: String?
    let accentColor: String?
    let updatedAt: Date
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case emoji
        case accentColor = "accent_color"
        case updatedAt = "updated_at"
    }
}

enum EchoError: LocalizedError {
    case supabaseNotConfigured
    case notAuthenticated
    case decodingFailed
    case invalidEmailDomain
    case invalidOrExpiredCode
    case functionError(String)
    case cannotMessageSelf
    case otpRequired

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured: return "Supabase no está configurado."
        case .notAuthenticated: return "Debes iniciar sesión."
        case .decodingFailed: return "Error al leer la respuesta."
        case .invalidEmailDomain: return "Usa un correo de tu universidad seleccionada."
        case .invalidOrExpiredCode: return "Código inválido o expirado."
        case .functionError(let msg): return msg
        case .cannotMessageSelf: return "No puedes enviarte mensaje a ti mismo."
        case .otpRequired: return "Verifica tu correo institucional para entrar."
        }
    }
}
