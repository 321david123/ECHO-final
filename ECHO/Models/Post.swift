//
//  Post.swift
//  ECHO
//

import Foundation
import SwiftUI

/// Palette of avatar background tints a user can choose. Stored as `rawValue` string in Supabase.
/// `gold` is exclusive: unlocked at 5 completed referrals ("Invita y Gana").
enum AccentColor: String, CaseIterable, Hashable {
    case green, blue, purple, pink, orange, yellow, teal, red, gold

    var color: Color {
        switch self {
        case .green: return Color.echoGreen
        case .blue: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .purple: return Color(red: 0.75, green: 0.55, blue: 1.0)
        case .pink: return Color(red: 1.0, green: 0.45, blue: 0.75)
        case .orange: return Color(red: 1.0, green: 0.6, blue: 0.35)
        case .yellow: return Color(red: 1.0, green: 0.85, blue: 0.4)
        case .teal: return Color(red: 0.4, green: 0.85, blue: 0.8)
        case .red: return Color(red: 1.0, green: 0.4, blue: 0.4)
        case .gold: return Color(red: 1.0, green: 0.76, blue: 0.22)
        }
    }

    /// True for colors that must be earned (not freely selectable).
    var isExclusive: Bool { self == .gold }
    
    /// Resolve from a stored string. Unknown or nil values fall back to `.green`.
    static func from(_ raw: String?) -> AccentColor {
        guard let raw = raw, let c = AccentColor(rawValue: raw) else { return .green }
        return c
    }
}

/// Optional poll attached to a post: question + option texts. Vote counts and "my vote" come from AppState/DB.
struct Poll: Equatable, Hashable {
    let question: String
    let options: [String]  // 2–6 options
    
    static let minOptions = 2
    static let maxOptions = 6
    static let maxQuestionLength = 120
}

/// A single anonymous post ("yak") in the feed.
struct Post: Identifiable, Equatable, Hashable {
    let id: UUID
    var body: String
    var score: Int
    var commentCount: Int
    var createdAt: Date
    var campusId: String
    var isHidden: Bool  // true after 5 downvotes (Yik Yak behavior)
    var imageURL: String?  // optional photo in Storage
    var isPinned: Bool
    /// Set when author signed in (for karma and "message author"); nil for legacy/anonymous.
    var authorId: UUID?
    /// Optional display name chosen by author at the time of posting. nil = show "Anónimo".
    var authorDisplayName: String?
    /// Optional emoji chosen by author at the time of posting. nil = show campus initial.
    var authorEmoji: String?
    /// Optional avatar tint chosen by author at the time of posting. nil = default green.
    var authorAccentColor: String?
    /// Optional poll (question + option texts). Vote counts and user's vote are in AppState.
    var poll: Poll?
    
    init(
        id: UUID = UUID(),
        body: String,
        score: Int = 0,
        commentCount: Int = 0,
        createdAt: Date = Date(),
        campusId: String,
        isHidden: Bool = false,
        imageURL: String? = nil,
        isPinned: Bool = false,
        authorId: UUID? = nil,
        authorDisplayName: String? = nil,
        authorEmoji: String? = nil,
        authorAccentColor: String? = nil,
        poll: Poll? = nil
    ) {
        self.id = id
        self.body = body
        self.score = score
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.campusId = campusId
        self.isHidden = isHidden
        self.imageURL = imageURL
        self.isPinned = isPinned
        self.authorId = authorId
        self.authorDisplayName = authorDisplayName
        self.authorEmoji = authorEmoji
        self.authorAccentColor = authorAccentColor
        self.poll = poll
    }
    
    /// Yik Yak: 200 character limit for posts.
    static let maxLength = 200
}
