//
//  Referral.swift
//  ECHO
//

import Foundation

/// A referral: `referrerId` invited `referredId` with `code`.
/// Completes when the invited user publishes their first echo.
struct Referral: Identifiable, Equatable {
    enum Status: String {
        case pending
        case completed
    }

    let id: UUID
    let referrerId: UUID
    let referredId: UUID
    let code: String
    let status: Status
    let createdAt: Date
    let completedAt: Date?
}

/// A drink earned in the "Invita y Gana" event (one per `referralsPerDrink` completed
/// referrals, unlimited). Admin marks it `delivered` after handing it over.
/// Digital prizes (OG badge at 1, gold profile at 5) derive from the completed count.
struct ReferralReward: Identifiable, Equatable {
    enum Status: String {
        case earned
        case delivered
    }

    let id: UUID
    let referralCountAtAward: Int
    let status: Status
    let createdAt: Date
}

/// Result statuses `claim_referral` can return (mirrors the SQL function).
enum ReferralClaimStatus: String {
    case ok
    case invalidCode = "invalid_code"
    case ownCode = "own_code"
    case alreadyReferred = "already_referred"
    case accountTooOld = "account_too_old"
    case notAuthenticated = "not_authenticated"

    /// User-facing message in Spanish (nil for .ok).
    var errorMessage: String? {
        switch self {
        case .ok: return nil
        case .invalidCode: return "Ese código no existe. Revísalo e intenta de nuevo."
        case .ownCode: return "No puedes usar tu propio código 😅"
        case .alreadyReferred: return "Ya registraste quién te invitó."
        case .accountTooOld: return "Este código solo aplica para cuentas nuevas."
        case .notAuthenticated: return "Debes iniciar sesión."
        }
    }
}
