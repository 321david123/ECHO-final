//
//  PrivateMessage.swift
//  ECHO
//

import Foundation

/// A single message in a private conversation.
struct PrivateMessage: Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let body: String
    let createdAt: Date
}
