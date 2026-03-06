//
//  Vote.swift
//  ECHO
//

import Foundation

enum VoteDirection: Int {
    case down = -1
    case none = 0
    case up = 1
}

/// User's vote on a post (stored locally; would be synced to backend).
struct UserVote: Equatable {
    let postId: UUID
    let direction: VoteDirection
}
