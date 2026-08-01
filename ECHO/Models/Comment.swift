//
//  Comment.swift
//  ECHO
//

import Foundation

struct Comment: Identifiable, Equatable {
    let id: UUID
    var body: String
    var postId: UUID
    var score: Int
    var createdAt: Date
    /// Author id (set when authenticated). Used to enable "Send DM" from a comment.
    var authorId: UUID?
    /// When non-nil, this comment is a reply to another comment (one-level threads).
    var parentCommentId: UUID?
    
    init(
        id: UUID = UUID(),
        body: String,
        postId: UUID,
        score: Int = 0,
        createdAt: Date = Date(),
        authorId: UUID? = nil,
        parentCommentId: UUID? = nil
    ) {
        self.id = id
        self.body = body
        self.postId = postId
        self.score = score
        self.createdAt = createdAt
        self.authorId = authorId
        self.parentCommentId = parentCommentId
    }
}
