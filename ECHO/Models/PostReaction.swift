//
//  PostReaction.swift
//  ECHO
//

import Foundation

/// Extra reactions on a post besides up/down votes.
/// Each user may use each reaction type at most once per UTC day (across the whole app).
enum PostReactionType: String, CaseIterable, Hashable {
    case fire = "fire"
    case laugh = "laugh"
    case hundred = "hundred"
    
    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .laugh: return "😂"
        case .hundred: return "💯"
        }
    }
    
    static func from(_ raw: String) -> PostReactionType? {
        PostReactionType(rawValue: raw)
    }
}
