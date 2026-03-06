//
//  DatabaseService.swift
//  ECHO
//

import Foundation
import Supabase

/// Fetches and writes posts, comments, votes from Supabase. All calls require auth and profile (campus).
final class DatabaseService: ObservableObject {
    private var client: Supabase.SupabaseClient? { SupabaseClient.shared }
    private let auth: AuthService
    
    init(authService: AuthService) {
        self.auth = authService
    }
    
    // MARK: - Posts
    
    /// Fetch visible posts for a campus, sorted by hot or new.
    func fetchPosts(campusId: String, sortHot: Bool) async throws -> [PostRow] {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let rows: [PostRow]
        if sortHot {
            rows = try await client
                .from("posts")
                .select()
                .eq("campus_id", value: campusId)
                .eq("is_hidden", value: false)
                .order("score", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        } else {
            rows = try await client
                .from("posts")
                .select()
                .eq("campus_id", value: campusId)
                .eq("is_hidden", value: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        }
        return rows
    }
    
    /// Upload image to Storage bucket "post-images" under folder "private" (matches Supabase policy template).
    func uploadPostImage(data: Data, fileExtension: String) async throws -> String {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let path = "private/\(UUID().uuidString).\(fileExtension)"
        try await client.storage
            .from("post-images")
            .upload(path, data: data, options: .init(contentType: mimeType(for: fileExtension)))
        let url = try client.storage.from("post-images").getPublicURL(path: path).absoluteString
        return url
    }
    
    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "image/jpeg"
        }
    }
    
    /// Insert a new post (body, campus_id; optional image_url, poll; author_id from session for karma).
    func insertPost(body: String, campusId: String, imageURL: String? = nil, pollQuestion: String? = nil, pollOptions: [String]? = nil) async throws -> PostRow {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let authorId = await auth.getCurrentUserId()
        let payload = PostInsert(body: body, campusId: campusId, authorId: authorId, imageUrl: imageURL, pollQuestion: pollQuestion, pollOptions: pollOptions)
        let response: PostRow = try await client
            .from("posts")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }
    
    // MARK: - Poll votes
    /// Vote counts per option for the given posts. Key: postId, value: [optionIndex: count].
    func fetchPollVoteCounts(postIds: [UUID]) async throws -> [UUID: [Int: Int]] {
        guard let client = client, !postIds.isEmpty else { return [:] }
        let ids = postIds.map(\.uuidString)
        struct PollVoteRow: Codable {
            let postId: UUID
            let optionIndex: Int
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case optionIndex = "option_index"
            }
        }
        var rows: [PollVoteRow] = []
        for id in ids {
            let part: [PollVoteRow] = try await client
                .from("poll_votes")
                .select("post_id,option_index")
                .eq("post_id", value: id)
                .execute()
                .value
            rows.append(contentsOf: part)
        }
        var result: [UUID: [Int: Int]] = [:]
        for postId in postIds { result[postId] = [:] }
        for r in rows {
            result[r.postId, default: [:]][r.optionIndex, default: 0] += 1
        }
        return result
    }
    
    /// Current user's vote for each post. Key: postId, value: optionIndex.
    func fetchMyPollVotes(postIds: [UUID]) async throws -> [UUID: Int] {
        guard let client = client, let uid = await auth.getCurrentUserId(), !postIds.isEmpty else { return [:] }
        struct Row: Codable {
            let postId: UUID
            let optionIndex: Int
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case optionIndex = "option_index"
            }
        }
        var result: [UUID: Int] = [:]
        for id in postIds {
            let rows: [Row] = try await client
                .from("poll_votes")
                .select("post_id,option_index")
                .eq("post_id", value: id)
                .eq("user_id", value: uid.uuidString)
                .execute()
                .value
            if let r = rows.first { result[r.postId] = r.optionIndex }
        }
        return result
    }
    
    /// Record or update user's poll vote (one vote per user per post). Upsert by (post_id, user_id).
    func votePoll(postId: UUID, optionIndex: Int) async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        struct PollVoteInsert: Encodable {
            let postId: UUID
            let userId: UUID
            let optionIndex: Int
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case userId = "user_id"
                case optionIndex = "option_index"
            }
        }
        let payload = PollVoteInsert(postId: postId, userId: uid, optionIndex: optionIndex)
        try await client
            .from("poll_votes")
            .upsert(payload, onConflict: "post_id,user_id")
            .execute()
    }
    
    // MARK: - Comments
    
    func fetchComments(postId: UUID) async throws -> [CommentRow] {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let rows: [CommentRow] = try await client
            .from("comments")
            .select()
            .eq("post_id", value: postId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        return rows
    }
    
    func insertComment(postId: UUID, body: String) async throws -> CommentRow {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let authorId = await auth.getCurrentUserId()
        let payload = CommentInsert(postId: postId, body: body, authorId: authorId)
        let response: CommentRow = try await client
            .from("comments")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }
    
    // MARK: - Votes
    
    /// Get current user's vote for a post (-1, 0, 1).
    func fetchMyVote(postId: UUID) async throws -> Int {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return 0 }
        let rows: [VoteRow] = try await client
            .from("votes")
            .select()
            .eq("user_id", value: uid.uuidString)
            .eq("post_id", value: postId.uuidString)
            .execute()
            .value
        return rows.first?.direction ?? 0
    }
    
    /// Fetch all current user's votes for given post IDs (to avoid N+1).
    func fetchMyVotes(postIds: [UUID]) async throws -> [UUID: Int] {
        guard let client = client, let uid = await auth.getCurrentUserId(), !postIds.isEmpty else { return [:] }
        let ids = postIds.map(\.uuidString)
        let rows: [VoteRow] = try await client
            .from("votes")
            .select()
            .eq("user_id", value: uid.uuidString)
            .in("post_id", values: ids)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { (UUID(uuidString: $0.postId)!, $0.direction) })
    }
    
    /// Set vote for post (direction: -1, 0, 1). Upserts into votes; trigger updates post score.
    func setVote(postId: UUID, direction: Int) async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return }
        let payload = VoteUpsert(userId: uid, postId: postId, direction: direction)
        try await client
            .from("votes")
            .upsert(payload, onConflict: "user_id,post_id")
            .execute()
    }
    
    // MARK: - Karma
    
    /// Sum of scores of posts where author_id = current user.
    func fetchMyKarma() async throws -> Int {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return 0 }
        let rows: [PostScoreRow] = try await client
            .from("posts")
            .select("score")
            .eq("author_id", value: uid.uuidString)
            .execute()
            .value
        return rows.map(\.score).reduce(0, +)
    }
    
    // MARK: - Private messages (only from a post)
    
    /// Find or create conversation: current user is initiator, messaging the post author. Fails if post author is self.
    func getOrCreateConversation(postId: UUID, postAuthorId: UUID) async throws -> ConversationRow {
        guard let client = client, let me = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        if me == postAuthorId { throw EchoError.cannotMessageSelf }
        let existing: [ConversationRow] = try await client
            .from("conversations")
            .select(conversationSelectColumns)
            .eq("post_id", value: postId.uuidString)
            .eq("initiator_id", value: me.uuidString)
            .execute()
            .value
        if let first = existing.first { return first }
        let payload = ConversationInsert(postId: postId, postAuthorId: postAuthorId, initiatorId: me)
        let row: ConversationRow = try await client
            .from("conversations")
            .insert(payload)
            .select(conversationSelectColumns)
            .single()
            .execute()
            .value
        return row
    }
    
    private let conversationSelectColumns = "id, post_id, post_author_id, initiator_id, created_at, posts(body)"
    
    /// All conversations where current user is participant (initiator or post author).
    func fetchMyConversations() async throws -> [ConversationRow] {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return [] }
        let rows: [ConversationRow] = try await client
            .from("conversations")
            .select(conversationSelectColumns)
            .or("post_author_id.eq.\(uid.uuidString),initiator_id.eq.\(uid.uuidString)")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }
    
    func fetchMessages(conversationId: UUID) async throws -> [PrivateMessageRow] {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let rows: [PrivateMessageRow] = try await client
            .from("private_messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        return rows
    }
    
    func sendMessage(conversationId: UUID, body: String) async throws -> PrivateMessageRow {
        guard let client = client, let uid = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        let payload = PrivateMessageInsert(conversationId: conversationId, senderId: uid, body: String(body.prefix(1000)))
        let row: PrivateMessageRow = try await client
            .from("private_messages")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return row
    }
    
    // MARK: - Push notifications
    /// Register or update the current user's device token for push. Call after receiving the APNs token.
    func saveDeviceToken(_ deviceToken: String, platform: String = "ios") async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return }
        let payload = DeviceTokenUpsert(userId: uid, deviceToken: deviceToken, platform: platform)
        try await client
            .from("device_tokens")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }
}

// MARK: - Supabase row types (Codable for API)

/// Minimal row for karma query (only score selected).
struct PostScoreRow: Codable {
    let score: Int
}

struct PostRow: Codable {
    let id: UUID
    let body: String
    let authorId: UUID?
    let campusId: String
    let score: Int
    let commentCount: Int
    let isHidden: Bool
    let imageUrl: String?
    let createdAtString: String?
    let pollQuestion: String?
    let pollOptions: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id, body, score
        case authorId = "author_id"
        case campusId = "campus_id"
        case commentCount = "comment_count"
        case isHidden = "is_hidden"
        case imageUrl = "image_url"
        case createdAtString = "created_at"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
    }
    
    var createdAt: Date {
        createdAtString.flatMap { Self.parseISO8601($0) } ?? Date()
    }
    private static func parseISO8601(_ s: String) -> Date? {
        iso8601WithFractional.date(from: s) ?? iso8601Plain.date(from: s)
    }
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

struct CommentRow: Codable {
    let id: UUID
    let postId: UUID
    let body: String
    let score: Int
    let createdAtString: String?
    
    enum CodingKeys: String, CodingKey {
        case id, body, score
        case postId = "post_id"
        case createdAtString = "created_at"
    }
    
    var createdAt: Date {
        createdAtString.flatMap { Self.parseISO8601($0) } ?? Date()
    }
    private static func parseISO8601(_ s: String) -> Date? {
        iso8601WithFractional.date(from: s) ?? iso8601Plain.date(from: s)
    }
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

struct VoteRow: Codable {
    let userId: String
    let postId: String
    let direction: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case postId = "post_id"
        case direction
    }
}

/// Nested in ConversationRow when selecting conversations with posts(body).
struct PostBodyEmbed: Codable {
    let body: String?
}

struct ConversationRow: Codable {
    let id: UUID
    let postId: UUID
    let postAuthorId: UUID
    let initiatorId: UUID
    let createdAtString: String?
    let posts: PostBodyEmbed?
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case postAuthorId = "post_author_id"
        case initiatorId = "initiator_id"
        case createdAtString = "created_at"
        case posts
    }
    
    var createdAt: Date {
        createdAtString.flatMap { Self.parseISO8601($0) } ?? Date()
    }
    private static func parseISO8601(_ s: String) -> Date? {
        iso8601WithFractional.date(from: s) ?? iso8601Plain.date(from: s)
    }
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

struct PrivateMessageRow: Codable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let body: String
    let createdAtString: String?
    
    enum CodingKeys: String, CodingKey {
        case id, body
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case createdAtString = "created_at"
    }
    
    var createdAt: Date {
        createdAtString.flatMap { Self.parseISO8601($0) } ?? Date()
    }
    private static func parseISO8601(_ s: String) -> Date? {
        iso8601WithFractional.date(from: s) ?? iso8601Plain.date(from: s)
    }
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

private struct ConversationInsert: Encodable {
    let postId: UUID
    let postAuthorId: UUID
    let initiatorId: UUID
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case postAuthorId = "post_author_id"
        case initiatorId = "initiator_id"
    }
}

private struct PrivateMessageInsert: Encodable {
    let conversationId: UUID
    let senderId: UUID
    let body: String
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case body
    }
}

private struct PostInsert: Encodable {
    let body: String
    let campusId: String
    let authorId: UUID?
    let imageUrl: String?
    let pollQuestion: String?
    let pollOptions: [String]?
    enum CodingKeys: String, CodingKey {
        case body
        case campusId = "campus_id"
        case authorId = "author_id"
        case imageUrl = "image_url"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
    }
}

private struct CommentInsert: Encodable {
    let postId: UUID
    let body: String
    let authorId: UUID?
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case body
        case authorId = "author_id"
    }
}

// MARK: - Row to app model conversion

extension PostRow {
    func toPost() -> Post {
        let poll: Poll? = {
            guard let q = pollQuestion, !q.isEmpty, let opts = pollOptions, opts.count >= Poll.minOptions else { return nil }
            return Poll(question: q, options: opts)
        }()
        return Post(
            id: id,
            body: body,
            score: score,
            commentCount: commentCount,
            createdAt: createdAt,
            campusId: campusId,
            isHidden: isHidden,
            imageURL: imageUrl,
            authorId: authorId,
            poll: poll
        )
    }
}

extension CommentRow {
    func toComment() -> Comment {
        Comment(
            id: id,
            body: body,
            postId: postId,
            score: score,
            createdAt: createdAt
        )
    }
}

extension ConversationRow {
    func toConversation() -> Conversation {
        let snippet = (posts?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = snippet.count > 80 ? String(snippet.prefix(80)) + "…" : snippet
        return Conversation(
            id: id,
            postId: postId,
            postBodySnippet: truncated.isEmpty ? "Post" : truncated,
            postAuthorId: postAuthorId,
            initiatorId: initiatorId,
            createdAt: createdAt,
            lastMessageAt: nil,
            lastMessageBody: nil
        )
    }
}

extension PrivateMessageRow {
    func toPrivateMessage() -> PrivateMessage {
        PrivateMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            body: body,
            createdAt: createdAt
        )
    }
}

private struct VoteUpsert: Encodable {
    let userId: UUID
    let postId: UUID
    let direction: Int
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case postId = "post_id"
        case direction
    }
}

private struct DeviceTokenUpsert: Encodable {
    let userId: UUID
    let deviceToken: String
    let platform: String
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case deviceToken = "device_token"
        case platform
    }
}
