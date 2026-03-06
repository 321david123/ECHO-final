//
//  Conversation.swift
//  ECHO
//

import Foundation

/// A private conversation started from a post (initiator messaged the post author).
struct Conversation: Identifiable, Equatable, Hashable {
    let id: UUID
    let postId: UUID
    let postBodySnippet: String  // truncated for list display
    let postAuthorId: UUID
    let initiatorId: UUID
    let createdAt: Date
    var lastMessageAt: Date?
    var lastMessageBody: String?
}
