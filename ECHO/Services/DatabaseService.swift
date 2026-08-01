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
    
    /// Fetch a single post by id (used for deep-linking from push).
    func fetchPost(id: UUID) async throws -> PostRow? {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let rows: [PostRow] = try await client
            .from("posts")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }
    
    /// Full-text search posts in a campus.
    func searchPosts(campusId: String, query: String) async throws -> [PostRow] {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Use ILIKE for partial matches (works without configuring websearch_to_tsquery).
        let pattern = "%\(trimmed)%"
        let rows: [PostRow] = try await client
            .from("posts")
            .select()
            .eq("campus_id", value: campusId)
            .eq("is_hidden", value: false)
            .ilike("body", pattern: pattern)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
        return rows
    }
    
    /// Posts that contain the given hashtag, in the user's campus.
    func fetchPostsByTag(campusId: String, tag: String) async throws -> [PostRow] {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        struct TagRow: Codable { let postId: UUID; enum CodingKeys: String, CodingKey { case postId = "post_id" } }
        let tagRows: [TagRow] = try await client
            .from("post_tags")
            .select("post_id")
            .eq("tag", value: tag.lowercased())
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        let ids = tagRows.map { $0.postId.uuidString }
        guard !ids.isEmpty else { return [] }
        let rows: [PostRow] = try await client
            .from("posts")
            .select()
            .in("id", values: ids)
            .eq("campus_id", value: campusId)
            .eq("is_hidden", value: false)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }
    
    /// Top hashtags in the user's campus over the last N days.
    func fetchTrendingTags(campusId: String, limit: Int = 12, sinceDays: Int = 14) async throws -> [(tag: String, count: Int)] {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(sinceDays * 86400)))
        struct TagPostRow: Codable { let tag: String; let postId: UUID; enum CodingKeys: String, CodingKey { case tag; case postId = "post_id" } }
        let rows: [TagPostRow] = try await client
            .from("post_tags")
            .select("tag,post_id")
            .gte("created_at", value: since)
            .limit(500)
            .execute()
            .value
        // Group client-side. (Could do it server-side via RPC for performance.)
        var counts: [String: Int] = [:]
        for r in rows { counts[r.tag, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }
    
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
    func insertPost(body: String, campusId: String, imageURL: String? = nil, pollQuestion: String? = nil, pollOptions: [String]? = nil, authorDisplayName: String? = nil, authorEmoji: String? = nil, authorAccentColor: String? = nil) async throws -> PostRow {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let authorId = await auth.getCurrentUserId()
        let payload = PostInsert(body: body, campusId: campusId, authorId: authorId, imageUrl: imageURL, pollQuestion: pollQuestion, pollOptions: pollOptions, authorDisplayName: authorDisplayName, authorEmoji: authorEmoji, authorAccentColor: authorAccentColor)
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
    /// Single query with `.in` (was one query per post).
    func fetchPollVoteCounts(postIds: [UUID]) async throws -> [UUID: [Int: Int]] {
        guard let client = client, !postIds.isEmpty else { return [:] }
        struct PollVoteRow: Codable {
            let postId: UUID
            let optionIndex: Int
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case optionIndex = "option_index"
            }
        }
        let rows: [PollVoteRow] = try await client
            .from("poll_votes")
            .select("post_id,option_index")
            .in("post_id", values: postIds.map(\.uuidString))
            .execute()
            .value
        var result: [UUID: [Int: Int]] = [:]
        for postId in postIds { result[postId] = [:] }
        for r in rows {
            result[r.postId, default: [:]][r.optionIndex, default: 0] += 1
        }
        return result
    }

    /// Current user's vote for each post. Key: postId, value: optionIndex. Single query.
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
        let rows: [Row] = try await client
            .from("poll_votes")
            .select("post_id,option_index")
            .eq("user_id", value: uid.uuidString)
            .in("post_id", values: postIds.map(\.uuidString))
            .execute()
            .value
        var result: [UUID: Int] = [:]
        for r in rows { result[r.postId] = r.optionIndex }
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
    
    func insertComment(postId: UUID, body: String, parentCommentId: UUID? = nil) async throws -> CommentRow {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let authorId = await auth.getCurrentUserId()
        let payload = CommentInsert(postId: postId, body: body, authorId: authorId, parentCommentId: parentCommentId)
        let response: CommentRow = try await client
            .from("comments")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }
    
    // MARK: - Reports
    
    func reportPost(postId: UUID, reason: String?) async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        struct ReportInsert: Encodable {
            let reporterId: UUID
            let postId: UUID
            let reason: String?
            enum CodingKeys: String, CodingKey {
                case reporterId = "reporter_id"
                case postId = "post_id"
                case reason
            }
        }
        try await client
            .from("reports")
            .insert(ReportInsert(reporterId: uid, postId: postId, reason: reason))
            .execute()
    }
    
    func reportComment(commentId: UUID, reason: String?) async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        struct ReportInsert: Encodable {
            let reporterId: UUID
            let commentId: UUID
            let reason: String?
            enum CodingKeys: String, CodingKey {
                case reporterId = "reporter_id"
                case commentId = "comment_id"
                case reason
            }
        }
        try await client
            .from("reports")
            .insert(ReportInsert(reporterId: uid, commentId: commentId, reason: reason))
            .execute()
    }
    
    // MARK: - Post reactions (extra: 🔥 😂 💯)
    
    /// Add a reaction to a post. Hits the daily-per-type uniqueness constraint server-side.
    /// Throws if the user already used this reaction type today.
    func addPostReaction(postId: UUID, type: PostReactionType) async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        struct ReactionInsert: Encodable {
            let postId: UUID
            let userId: UUID
            let reaction: String
            enum CodingKeys: String, CodingKey {
                case postId = "post_id"
                case userId = "user_id"
                case reaction
            }
        }
        let payload = ReactionInsert(postId: postId, userId: uid, reaction: type.rawValue)
        try await client
            .from("post_reactions")
            .insert(payload)
            .execute()
    }
    
    /// Counts of each reaction for the given posts. Returns [postId: [type: count]].
    func fetchPostReactionCounts(postIds: [UUID]) async throws -> [UUID: [PostReactionType: Int]] {
        guard let client = client, !postIds.isEmpty else { return [:] }
        struct Row: Codable { let postId: UUID; let reaction: String; enum CodingKeys: String, CodingKey { case postId = "post_id"; case reaction } }
        let ids = postIds.map { $0.uuidString }
        let rows: [Row] = try await client
            .from("post_reactions")
            .select("post_id,reaction")
            .in("post_id", values: ids)
            .execute()
            .value
        var result: [UUID: [PostReactionType: Int]] = [:]
        for id in postIds { result[id] = [:] }
        for r in rows {
            guard let t = PostReactionType.from(r.reaction) else { continue }
            result[r.postId, default: [:]][t, default: 0] += 1
        }
        return result
    }
    
    /// Reactions the current user used today (UTC). Used to disable buttons in UI.
    func fetchMyReactionsToday() async throws -> Set<PostReactionType> {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return [] }
        // UTC start of day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let startOfUTCDay = calendar.startOfDay(for: Date())
        let iso = ISO8601DateFormatter().string(from: startOfUTCDay)
        struct Row: Codable { let reaction: String }
        let rows: [Row] = try await client
            .from("post_reactions")
            .select("reaction")
            .eq("user_id", value: uid.uuidString)
            .gte("created_at", value: iso)
            .execute()
            .value
        return Set(rows.compactMap { PostReactionType.from($0.reaction) })
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
    
    // MARK: - Comment votes
    
    func fetchMyCommentVotes(commentIds: [UUID]) async throws -> [UUID: Int] {
        guard let client = client, let uid = await auth.getCurrentUserId(), !commentIds.isEmpty else { return [:] }
        let ids = commentIds.map(\.uuidString)
        let rows: [CommentVoteRow] = try await client
            .from("comment_votes")
            .select()
            .eq("user_id", value: uid.uuidString)
            .in("comment_id", values: ids)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.map { (UUID(uuidString: $0.commentId)!, $0.direction) })
    }
    
    func setCommentVote(commentId: UUID, direction: Int) async throws {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return }
        let payload = CommentVoteUpsert(userId: uid, commentId: commentId, direction: direction)
        try await client
            .from("comment_votes")
            .upsert(payload, onConflict: "user_id,comment_id")
            .execute()
    }
    
    // MARK: - Karma
    
    /// Sum of scores of all posts + comments authored by the current user.
    func fetchMyKarma() async throws -> Int {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return 0 }
        let postRows: [PostScoreRow] = try await client
            .from("posts")
            .select("score")
            .eq("author_id", value: uid.uuidString)
            .execute()
            .value
        let commentRows: [PostScoreRow] = try await client
            .from("comments")
            .select("score")
            .eq("author_id", value: uid.uuidString)
            .execute()
            .value
        return postRows.map(\.score).reduce(0, +) + commentRows.map(\.score).reduce(0, +)
    }
    
    // MARK: - Private messages (only from a post)
    
    /// Find or create conversation: current user is initiator, messaging the post author. Fails if post author is self.
    /// "Post-level" conversations have comment_id NULL.
    func getOrCreateConversation(postId: UUID, postAuthorId: UUID) async throws -> ConversationRow {
        guard let client = client, let me = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        if me == postAuthorId { throw EchoError.cannotMessageSelf }
        let existing: [ConversationRow] = try await client
            .from("conversations")
            .select(conversationSelectColumns)
            .eq("post_id", value: postId.uuidString)
            .eq("initiator_id", value: me.uuidString)
            .is("comment_id", value: nil)
            .execute()
            .value
        if let first = existing.first { return first }
        let payload = ConversationInsert(postId: postId, postAuthorId: postAuthorId, initiatorId: me, commentId: nil)
        let row: ConversationRow = try await client
            .from("conversations")
            .insert(payload)
            .select(conversationSelectColumns)
            .single()
            .execute()
            .value
        return row
    }
    
    /// Find or create a DM with the author of a specific comment (recipient = comment author).
    /// Allows multiple conversations per post (one per recipient/comment).
    func getOrCreateConversationFromComment(postId: UUID, commentAuthorId: UUID, commentId: UUID) async throws -> ConversationRow {
        guard let client = client, let me = await auth.getCurrentUserId() else { throw EchoError.supabaseNotConfigured }
        if me == commentAuthorId { throw EchoError.cannotMessageSelf }
        let existing: [ConversationRow] = try await client
            .from("conversations")
            .select(conversationSelectColumns)
            .eq("post_id", value: postId.uuidString)
            .eq("initiator_id", value: me.uuidString)
            .eq("comment_id", value: commentId.uuidString)
            .execute()
            .value
        if let first = existing.first { return first }
        let payload = ConversationInsert(postId: postId, postAuthorId: commentAuthorId, initiatorId: me, commentId: commentId)
        let row: ConversationRow = try await client
            .from("conversations")
            .insert(payload)
            .select(conversationSelectColumns)
            .single()
            .execute()
            .value
        return row
    }
    
    private let conversationSelectColumns = "id, post_id, post_author_id, initiator_id, comment_id, created_at, posts(body), comments(body)"
    
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
    
    /// Latest message per conversation, in one query (used to sort Mensajes by recency
    /// and show a preview). Fetches newest-first and keeps the first row per conversation.
    func fetchLatestMessages(conversationIds: [UUID]) async throws -> [UUID: PrivateMessageRow] {
        guard let client = client, !conversationIds.isEmpty else { return [:] }
        let rows: [PrivateMessageRow] = try await client
            .from("private_messages")
            .select()
            .in("conversation_id", values: conversationIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .limit(400)
            .execute()
            .value
        var latest: [UUID: PrivateMessageRow] = [:]
        for row in rows where latest[row.conversationId] == nil {
            latest[row.conversationId] = row
        }
        return latest
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
    
    // MARK: - Referrals ("Invita y Gana")

    /// Get (or lazily create) the current user's referral code via RPC.
    func ensureReferralCode() async throws -> String {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        let code: String = try await client
            .rpc("ensure_referral_code")
            .execute()
            .value
        return code
    }

    /// Referrals where the current user is the referrer (RLS limits rows to own).
    func fetchMyReferrals() async throws -> [ReferralRow] {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return [] }
        let rows: [ReferralRow] = try await client
            .from("referrals")
            .select()
            .eq("referrer_id", value: uid.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    /// The referral where the current user is the *referred* one (nil if never claimed a code).
    func fetchMyReferralClaim() async throws -> ReferralRow? {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return nil }
        let rows: [ReferralRow] = try await client
            .from("referrals")
            .select()
            .eq("referred_id", value: uid.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// Rewards (drinks) the current user has earned.
    func fetchMyReferralRewards() async throws -> [ReferralRewardRow] {
        guard let client = client, let uid = await auth.getCurrentUserId() else { return [] }
        let rows: [ReferralRewardRow] = try await client
            .from("referral_rewards")
            .select()
            .eq("user_id", value: uid.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows
    }

    /// Claim a friend's code as a new user. Server enforces: account < 7 days,
    /// not own code, one referrer per user. Returns the server status.
    func claimReferral(code: String) async throws -> ReferralClaimStatus {
        guard let client = client else { throw EchoError.supabaseNotConfigured }
        struct ClaimResponse: Decodable {
            let status: String
            let completed: Bool?
        }
        let response: ClaimResponse = try await client
            .rpc("claim_referral", params: ["p_code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
            .execute()
            .value
        return ReferralClaimStatus(rawValue: response.status) ?? .invalidCode
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
    let isPinned: Bool?
    let imageUrl: String?
    let createdAtString: String?
    let pollQuestion: String?
    let pollOptions: [String]?
    let authorDisplayName: String?
    let authorEmoji: String?
    let authorAccentColor: String?
    
    enum CodingKeys: String, CodingKey {
        case id, body, score
        case authorId = "author_id"
        case campusId = "campus_id"
        case commentCount = "comment_count"
        case isHidden = "is_hidden"
        case isPinned = "is_pinned"
        case imageUrl = "image_url"
        case createdAtString = "created_at"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
        case authorDisplayName = "author_display_name"
        case authorEmoji = "author_emoji"
        case authorAccentColor = "author_accent_color"
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
    let authorId: UUID?
    let parentCommentId: UUID?
    let createdAtString: String?
    
    enum CodingKeys: String, CodingKey {
        case id, body, score
        case postId = "post_id"
        case authorId = "author_id"
        case parentCommentId = "parent_comment_id"
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
    let commentId: UUID?
    let createdAtString: String?
    let posts: PostBodyEmbed?
    let comments: PostBodyEmbed?
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case postAuthorId = "post_author_id"
        case initiatorId = "initiator_id"
        case commentId = "comment_id"
        case createdAtString = "created_at"
        case posts
        case comments
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
    let commentId: UUID?
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case postAuthorId = "post_author_id"
        case initiatorId = "initiator_id"
        case commentId = "comment_id"
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
    let authorDisplayName: String?
    let authorEmoji: String?
    let authorAccentColor: String?
    enum CodingKeys: String, CodingKey {
        case body
        case campusId = "campus_id"
        case authorId = "author_id"
        case imageUrl = "image_url"
        case pollQuestion = "poll_question"
        case pollOptions = "poll_options"
        case authorDisplayName = "author_display_name"
        case authorEmoji = "author_emoji"
        case authorAccentColor = "author_accent_color"
    }
}

private struct CommentInsert: Encodable {
    let postId: UUID
    let body: String
    let authorId: UUID?
    let parentCommentId: UUID?
    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case body
        case authorId = "author_id"
        case parentCommentId = "parent_comment_id"
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
            isPinned: isPinned ?? false,
            authorId: authorId,
            authorDisplayName: authorDisplayName,
            authorEmoji: authorEmoji,
            authorAccentColor: authorAccentColor,
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
            createdAt: createdAt,
            authorId: authorId,
            parentCommentId: parentCommentId
        )
    }
}

extension ConversationRow {
    func toConversation() -> Conversation {
        // For comment-based conversations, prefer the comment body as snippet; fall back to the post body.
        let raw = (commentId != nil
                   ? (comments?.body ?? posts?.body ?? "")
                   : (posts?.body ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = raw.count > 80 ? String(raw.prefix(80)) + "…" : raw
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

struct CommentVoteRow: Codable {
    let userId: String
    let commentId: String
    let direction: Int
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case commentId = "comment_id"
        case direction
    }
}

// MARK: - Referral rows

struct ReferralRow: Codable {
    let id: UUID
    let referrerId: UUID
    let referredId: UUID
    let code: String
    let status: String
    let createdAtString: String?
    let completedAtString: String?

    enum CodingKeys: String, CodingKey {
        case id, code, status
        case referrerId = "referrer_id"
        case referredId = "referred_id"
        case createdAtString = "created_at"
        case completedAtString = "completed_at"
    }

    var createdAt: Date { createdAtString.flatMap { Self.parseISO8601($0) } ?? Date() }
    var completedAt: Date? { completedAtString.flatMap { Self.parseISO8601($0) } }
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

    func toReferral() -> Referral {
        Referral(
            id: id,
            referrerId: referrerId,
            referredId: referredId,
            code: code,
            status: Referral.Status(rawValue: status) ?? .pending,
            createdAt: createdAt,
            completedAt: completedAt
        )
    }
}

struct ReferralRewardRow: Codable {
    let id: UUID
    let referralCountAtAward: Int
    let status: String
    let createdAtString: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case referralCountAtAward = "referral_count_at_award"
        case createdAtString = "created_at"
    }

    var createdAt: Date { createdAtString.flatMap { Self.parseISO8601($0) } ?? Date() }
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

    func toReferralReward() -> ReferralReward {
        ReferralReward(
            id: id,
            referralCountAtAward: referralCountAtAward,
            status: ReferralReward.Status(rawValue: status) ?? .earned,
            createdAt: createdAt
        )
    }
}

private struct CommentVoteUpsert: Encodable {
    let userId: UUID
    let commentId: UUID
    let direction: Int
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case commentId = "comment_id"
        case direction
    }
}
