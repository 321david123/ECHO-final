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
    
    init(
        id: UUID = UUID(),
        body: String,
        postId: UUID,
        score: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.body = body
        self.postId = postId
        self.score = score
        self.createdAt = createdAt
    }
}
