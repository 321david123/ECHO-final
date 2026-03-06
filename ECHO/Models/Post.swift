//
//  Post.swift
//  ECHO
//

import Foundation

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
    /// Set when author signed in (for karma and "message author"); nil for legacy/anonymous.
    var authorId: UUID?
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
        authorId: UUID? = nil,
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
        self.authorId = authorId
        self.poll = poll
    }
    
    /// Yik Yak: 200 character limit for posts.
    static let maxLength = 200
}
