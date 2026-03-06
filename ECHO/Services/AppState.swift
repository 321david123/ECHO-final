//
//  AppState.swift
//  ECHO
//

import Foundation
import SwiftUI
import UserNotifications

/// Global app state. Uses Supabase (auth + database) when configured; otherwise in-memory mock.
final class AppState: ObservableObject {
    // MARK: - Backend (when Supabase configured)
    private(set) var authService: AuthService?
    private(set) var databaseService: DatabaseService?
    var useSupabase: Bool { authService != nil && !isReviewerSession }
    
    /// When true, user logged in as reviewer (DEBUG only); feed uses mock data, no real Supabase auth.
    @Published var isReviewerSession: Bool = false
    
    // MARK: - Session & profile
    @Published var hasCompletedOnboarding: Bool = false
    /// When true, restoreSessionIfNeeded() has run at least once (so we know if we have a session or not).
    @Published var hasAttemptedRestore: Bool = false
    @Published var verifiedCampus: Campus?
    @Published var selectedCampus: Campus
    @Published var posts: [Post] = []
    @Published var comments: [Comment] = []
    @Published var userVotes: [UUID: VoteDirection] = [:]
    @Published var myPostIds: Set<UUID> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Set when Supabase session is restored (for "Message author" and message UI).
    @Published var currentUserId: UUID?
    
    @Published var conversations: [Conversation] = []
    @Published var messagesByConversation: [UUID: [PrivateMessage]] = [:]
    
    /// Poll vote counts per post. Key: postId, value: [optionIndex: count].
    @Published var pollVoteCounts: [UUID: [Int: Int]] = [:]
    /// Current user's poll vote per post. Key: postId, value: optionIndex.
    @Published var myPollVote: [UUID: Int] = [:]
    
    static let downvoteHideThreshold = 5
    
    var userKarma: Int {
        if useSupabase {
            return _cachedKarma
        }
        return posts.filter { myPostIds.contains($0.id) }.reduce(0) { $0 + $1.score }
    }
    @Published private var _cachedKarma: Int = 0
    
    private static let hasCompletedOnboardingKey = "ECHO_hasCompletedOnboarding"
    /// After sign out with Supabase, user must complete full OTP flow again (no restore into any campus).
    private static let requiresReauthAfterSignOutKey = "ECHO_requiresReauthAfterSignOut"
    
    /// When true, user signed out and must complete full OTP (campus → email → code) before entering again. @Published so UI always updates.
    @Published var requiresReauthAfterSignOut: Bool = false
    
    @Published var feedSort: FeedSort = .new
    /// When true, bottom tab bar is shown in compact mode (e.g. after scrolling down on feed).
    @Published var isTabBarCompact: Bool = false
    
    enum FeedSort: String, CaseIterable {
        case new = "Recientes"
        case hot = "Popular"
    }
    
    init() {
        self.selectedCampus = Campus.mexicanUniversities[0]
        self.verifiedCampus = nil
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
        self.requiresReauthAfterSignOut = UserDefaults.standard.bool(forKey: Self.requiresReauthAfterSignOutKey)
        if SupabaseConfig.isConfigured,
           let urlStr = SupabaseConfig.urlString,
           let url = URL(string: urlStr),
           let key = SupabaseConfig.anonKey {
            SupabaseClient.initialize(url: url, anonKey: key)
            let auth = AuthService()
            self.authService = auth
            self.databaseService = DatabaseService(authService: auth)
            auth.onAuthStateChange { [weak self] event, session in
                Task { @MainActor in await self?.restoreSessionIfNeeded() }
            }
            Task { @MainActor in await self.restoreSessionIfNeeded() }
            NotificationCenter.default.addObserver(forName: ECHOAppDelegate.didRegisterDeviceTokenNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.uploadDeviceTokenIfNeeded() }
            }
        } else {
            self.posts = []
            self.comments = []
            self.hasAttemptedRestore = true
        }
    }
    
    @MainActor
    private func restoreSessionIfNeeded() async {
        defer { hasAttemptedRestore = true }
        guard let auth = authService else { return }
        if requiresReauthAfterSignOut || UserDefaults.standard.bool(forKey: Self.requiresReauthAfterSignOutKey) {
            requiresReauthAfterSignOut = true
            UserDefaults.standard.set(true, forKey: Self.requiresReauthAfterSignOutKey)
            try? await auth.signOut()
            hasCompletedOnboarding = false
            UserDefaults.standard.set(false, forKey: Self.hasCompletedOnboardingKey)
            verifiedCampus = nil
            selectedCampus = Campus.mexicanUniversities[0]
            return
        }
        guard let session = try? await auth.getSession(), !session.isExpired else {
            hasCompletedOnboarding = false
            UserDefaults.standard.set(false, forKey: Self.hasCompletedOnboardingKey)
            return
        }
        guard let profile = try? await auth.fetchProfile() else {
            hasCompletedOnboarding = false
            UserDefaults.standard.set(false, forKey: Self.hasCompletedOnboardingKey)
            return
        }
        // Only restore if profile's campus_id matches a known campus. Otherwise force re-login so user picks the correct campus (e.g. Tec de Monterrey).
        let campus: Campus? = Campus.mexicanUniversities.first(where: { $0.id == profile.campusId })
            ?? Campus.mexicanUniversities.first(where: { profile.campusId.hasPrefix($0.id) || $0.id.hasPrefix(profile.campusId) })
        guard let campus = campus else {
            // Profile has unknown campus_id (wrong or stale). Sign out and require onboarding so they log in for the correct campus.
            try? await auth.signOut()
            hasCompletedOnboarding = false
            UserDefaults.standard.set(false, forKey: Self.hasCompletedOnboardingKey)
            verifiedCampus = nil
            selectedCampus = Campus.mexicanUniversities[0]
            posts = []
            comments = []
            userVotes = [:]
            myPostIds = []
            currentUserId = nil
            return
        }
        verifiedCampus = campus
        selectedCampus = campus
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        currentUserId = await auth.getCurrentUserId()
        await loadPosts()
        await loadKarma()
        await loadConversations()
        await registerPushNotificationsIfNeeded()
        await uploadDeviceTokenIfNeeded()
    }
    
    /// Request notification permission and register for remote notifications when user is logged in.
    private func registerPushNotificationsIfNeeded() async {
        guard useSupabase, verifiedCampus != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        case .authorized, .provisional:
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        case .denied, .ephemeral:
            break
        @unknown default:
            break
        }
    }
    
    /// Upload stored APNs token to Supabase (called when we receive the token in ECHOAppDelegate).
    private func uploadDeviceTokenIfNeeded() async {
        guard let token = ECHOAppDelegate.storedDeviceToken, let db = databaseService else { return }
        do {
            try await db.saveDeviceToken(token, platform: "ios")
            await MainActor.run { ECHOAppDelegate.clearStoredToken() }
        } catch { }
    }
    
    // MARK: - Feed
    /// Feed shows only posts for the user's verified campus (Supabase) or selected campus (mock). Never a random/other campus.
    var visiblePosts: [Post] {
        let campusId = (useSupabase ? verifiedCampus : selectedCampus)?.id ?? selectedCampus.id
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        var list = posts.filter { $0.campusId == campusId && !$0.isHidden }
        if feedSort == .hot {
            list = list.filter { $0.createdAt >= twoDaysAgo }
        }
        return list.sorted { p1, p2 in
            switch feedSort {
            case .new: return p1.createdAt > p2.createdAt
            case .hot: return (p1.score, p1.createdAt) > (p2.score, p2.createdAt)
            }
        }
    }
    
    func comments(for postId: UUID) -> [Comment] {
        comments.filter { $0.postId == postId }.sorted { $0.createdAt < $1.createdAt }
    }
    
    // MARK: - Auth (Supabase) — email OTP verification by campus
    /// Send OTP to institutional email for the selected campus.
    func sendOTP(email: String, campusId: String) async throws {
        guard let auth = authService else { throw EchoError.supabaseNotConfigured }
        try await auth.sendOTP(email: email, campusId: campusId)
    }
    
    /// Verify 6-digit OTP (WorkOS), complete session via magic link, create profile for campus.
    func enterWithEmailOTP(campus: Campus, email: String, code: String) async throws {
        guard let auth = authService else {
            completeOnboarding(verifiedCampus: campus)
            return
        }
        try await auth.verifyOTP(email: email, code: code, campusId: campus.id)
        guard let uid = await auth.getCurrentUserId() else { throw EchoError.notAuthenticated }
        try await auth.createProfile(userId: uid, campusId: campus.id)
        await MainActor.run {
            verifiedCampus = campus
            selectedCampus = campus
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
            requiresReauthAfterSignOut = false
            UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
            currentUserId = uid
        }
        await loadPosts()
        await loadMyVotes()
        await loadKarma()
        await loadConversations()
        await registerPushNotificationsIfNeeded()
        await uploadDeviceTokenIfNeeded()
    }
    
    /// Handle echo://auth/callback when app is opened via magic link (e.g. from Mail). Sets session, creates profile, completes onboarding.
    func handleAuthCallbackURL(_ url: URL) {
        guard url.scheme == "echo", url.host == "auth", url.path.hasPrefix("/callback") else { return }
        guard let auth = authService else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let campusId = components?.queryItems?.first(where: { $0.name == "campus_id" })?.value
        guard let campusId = campusId,
              let campus = Campus.mexicanUniversities.first(where: { $0.id == campusId }) else { return }
        Task { @MainActor in
            do {
                try await auth.setSessionFromCallbackURL(url)
                guard let uid = await auth.getCurrentUserId() else { return }
                try await auth.createProfile(userId: uid, campusId: campus.id)
                verifiedCampus = campus
                selectedCampus = campus
                hasCompletedOnboarding = true
                UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
                requiresReauthAfterSignOut = false
                UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
                currentUserId = uid
                await loadPosts()
                await loadMyVotes()
                await loadKarma()
                await loadConversations()
                await registerPushNotificationsIfNeeded()
                await uploadDeviceTokenIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    /// Anonymous entry (no OTP). Use only when Supabase not configured (mock). When Supabase is configured or user must reauth, OTP is required.
    func enterWithCampus(_ campus: Campus) async throws {
        if requiresReauthAfterSignOut || UserDefaults.standard.bool(forKey: Self.requiresReauthAfterSignOutKey) {
            throw EchoError.otpRequired
        }
        guard authService == nil else {
            throw EchoError.otpRequired
        }
        completeOnboarding(verifiedCampus: campus)
    }
    
    func signOut() async throws {
        let auth = authService
        // Set flag and clear state FIRST (on MainActor) so any auth state change / restore that runs when signOut() completes sees "must reauth" and does not restore.
        await MainActor.run {
            requiresReauthAfterSignOut = true
            UserDefaults.standard.set(true, forKey: Self.requiresReauthAfterSignOutKey)
            hasCompletedOnboarding = false
            UserDefaults.standard.set(false, forKey: Self.hasCompletedOnboardingKey)
            verifiedCampus = nil
            selectedCampus = Campus.mexicanUniversities[0]
            isReviewerSession = false
            posts = []
            comments = []
            userVotes = [:]
            myPostIds = []
            _cachedKarma = 0
            currentUserId = nil
            conversations = []
            messagesByConversation = [:]
        }
        if let auth = auth {
            try await auth.signOut()
        }
    }
    
    // MARK: - Load from Supabase
    func loadPosts() async {
        guard let db = databaseService, let campusId = verifiedCampus?.id else { return }
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }
        do {
            let rows = try await db.fetchPosts(campusId: campusId, sortHot: feedSort == .hot)
            let newPosts = rows.map { $0.toPost() }
            await MainActor.run { posts = newPosts }
            await loadMyVotes()
            await loadPollData()
            await loadKarma()
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func loadMyVotes() async {
        guard let db = databaseService, !posts.isEmpty else { return }
        do {
            let ids = posts.map(\.id)
            let map = try await db.fetchMyVotes(postIds: ids)
            await MainActor.run { userVotes = map.mapValues { VoteDirection(rawValue: $0) ?? .none } }
        } catch { }
    }
    
    func loadComments(for postId: UUID) async {
        guard let db = databaseService else { return }
        do {
            let rows = try await db.fetchComments(postId: postId)
            let newComments = rows.map { $0.toComment() }
            await MainActor.run {
                comments = comments.filter { $0.postId != postId } + newComments
            }
        } catch { }
    }
    
    private func loadKarma() async {
        guard let db = databaseService else { return }
        do {
            let k = try await db.fetchMyKarma()
            await MainActor.run { _cachedKarma = k }
        } catch { }
    }
    
    private func loadPollData() async {
        guard let db = databaseService else { return }
        let postIdsWithPoll = posts.filter { $0.poll != nil }.map(\.id)
        guard !postIdsWithPoll.isEmpty else { return }
        do {
            let counts = try await db.fetchPollVoteCounts(postIds: postIdsWithPoll)
            let myVotes = try await db.fetchMyPollVotes(postIds: postIdsWithPoll)
            await MainActor.run {
                pollVoteCounts = counts
                myPollVote = myVotes
            }
        } catch { }
    }
    
    func loadConversations() async {
        guard let db = databaseService else { return }
        do {
            let rows = try await db.fetchMyConversations()
            await MainActor.run { conversations = rows.map { $0.toConversation() } }
        } catch { }
    }
    
    func loadMessages(conversationId: UUID) async {
        guard let db = databaseService else { return }
        do {
            let rows = try await db.fetchMessages(conversationId: conversationId)
            await MainActor.run {
                messagesByConversation[conversationId] = rows.map { $0.toPrivateMessage() }
            }
        } catch { }
    }
    
    /// Find or create a conversation to message the post author. Call from a post detail (author must not be self).
    func getOrCreateConversation(postId: UUID, postAuthorId: UUID) async throws -> Conversation {
        guard let db = databaseService else { throw EchoError.supabaseNotConfigured }
        let row = try await db.getOrCreateConversation(postId: postId, postAuthorId: postAuthorId)
        let conv = row.toConversation()
        await MainActor.run {
            if !conversations.contains(where: { $0.id == conv.id }) {
                conversations.insert(conv, at: 0)
            }
        }
        await loadMessages(conversationId: conv.id)
        return conv
    }
    
    func sendMessage(conversationId: UUID, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let db = databaseService else { return }
        Task {
            do {
                let row = try await db.sendMessage(conversationId: conversationId, body: trimmed)
                await MainActor.run {
                    messagesByConversation[conversationId, default: []].append(row.toPrivateMessage())
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
    
    func messages(for conversationId: UUID) -> [PrivateMessage] {
        messagesByConversation[conversationId] ?? []
    }
    
    // MARK: - Actions
    func completeOnboarding(verifiedCampus: Campus) {
        self.verifiedCampus = verifiedCampus
        self.selectedCampus = verifiedCampus
        self.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        requiresReauthAfterSignOut = false
        UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
    }
    
    /// Completes onboarding for reviewers / devs (review@echoiosone.com + 123456); no real OTP. Feed loads from DB when possible; reviewer sees empty feed.
    func completeReviewerOnboarding(campus: Campus) {
        isReviewerSession = true
        verifiedCampus = campus
        selectedCampus = campus
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        requiresReauthAfterSignOut = false
        UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
        posts = []
        comments = []
    }
    
    /// Add a post. When using Supabase (and not reviewer session), inserts into DB. Use `addPostAsync` from UI to await and show errors.
    func addPost(_ body: String, imageData: Data? = nil, imageFileExtension: String = "jpg", poll: Poll? = nil) {
        let text = String(body.prefix(Post.maxLength))
        if let db = databaseService, !isReviewerSession {
            Task {
                do {
                    var imageURL: String? = nil
                    if let data = imageData {
                        imageURL = try await db.uploadPostImage(data: data, fileExtension: imageFileExtension)
                    }
                    let row = try await db.insertPost(body: text, campusId: selectedCampus.id, imageURL: imageURL, pollQuestion: poll?.question, pollOptions: poll?.options)
                    await MainActor.run {
                        posts.insert(row.toPost(), at: 0)
                        myPostIds.insert(row.id)
                    }
                    await loadPollData()
                    await loadKarma()
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        } else {
            let post = Post(body: text, campusId: selectedCampus.id, poll: poll)
            posts.insert(post, at: 0)
            myPostIds.insert(post.id)
        }
    }
    
    /// Call from UI to post and await result; throws on failure so you can show error and only dismiss on success.
    func addPostAsync(_ body: String, imageData: Data? = nil, imageFileExtension: String = "jpg", poll: Poll? = nil) async throws {
        let text = String(body.prefix(Post.maxLength))
        if let db = databaseService, !isReviewerSession {
            var imageURL: String? = nil
            if let data = imageData {
                imageURL = try await db.uploadPostImage(data: data, fileExtension: imageFileExtension)
            }
            let row = try await db.insertPost(body: text, campusId: selectedCampus.id, imageURL: imageURL, pollQuestion: poll?.question, pollOptions: poll?.options)
            await MainActor.run {
                posts.insert(row.toPost(), at: 0)
                myPostIds.insert(row.id)
            }
            await loadPollData()
            await loadKarma()
        } else {
            let post = Post(body: text, campusId: selectedCampus.id, poll: poll)
            await MainActor.run {
                posts.insert(post, at: 0)
                myPostIds.insert(post.id)
            }
        }
    }
    
    /// Vote on a poll option. One vote per user per post; refreshes poll data for that post.
    func votePoll(postId: UUID, optionIndex: Int) {
        guard let db = databaseService else { return }
        Task {
            do {
                try await db.votePoll(postId: postId, optionIndex: optionIndex)
                await loadPollData()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
    
    func pollVoteCount(for postId: UUID, optionIndex: Int) -> Int {
        pollVoteCounts[postId]?[optionIndex] ?? 0
    }
    
    func myPollVote(for postId: UUID) -> Int? {
        myPollVote[postId]
    }
    
    func addComment(_ body: String, postId: UUID) {
        if let db = databaseService {
            Task {
                do {
                    let row = try await db.insertComment(postId: postId, body: body)
                    await MainActor.run {
                        comments.append(row.toComment())
                        if let i = posts.firstIndex(where: { $0.id == postId }) {
                            posts[i].commentCount += 1
                        }
                    }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        } else {
            let comment = Comment(body: body, postId: postId)
            comments.append(comment)
            if let i = posts.firstIndex(where: { $0.id == postId }) {
                posts[i].commentCount += 1
            }
        }
    }
    
    func vote(postId: UUID, direction: VoteDirection) {
        if let db = databaseService {
            Task {
                do {
                    try await db.setVote(postId: postId, direction: direction.rawValue)
                    await MainActor.run { userVotes[postId] = direction }
                    await loadPosts()
                    await loadKarma()
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        } else {
            guard let i = posts.firstIndex(where: { $0.id == postId }) else { return }
            let prev = userVotes[postId] ?? .none
            posts[i].score -= prev.rawValue
            posts[i].score += direction.rawValue
            if direction == .none { userVotes.removeValue(forKey: postId) }
            else { userVotes[postId] = direction }
            if posts[i].score <= -Self.downvoteHideThreshold { posts[i].isHidden = true }
        }
    }
    
    func userVote(for postId: UUID) -> VoteDirection {
        userVotes[postId] ?? .none
    }
}
