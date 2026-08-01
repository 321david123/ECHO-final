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
    var useSupabase: Bool { authService != nil }
    
    /// When true, user logged in as reviewer (bypassed real OTP with reviewer code).
    @Published var isReviewerSession: Bool = false
    
    /// Prevents restoreSessionIfNeeded from interfering during an active login flow.
    private var isPerformingLogin = false
    
    // MARK: - Session & profile
    @Published var hasCompletedOnboarding: Bool = false
    /// When true, restoreSessionIfNeeded() has run at least once (so we know if we have a session or not).
    @Published var hasAttemptedRestore: Bool = false
    @Published var verifiedCampus: Campus?
    @Published var selectedCampus: Campus
    @Published var posts: [Post] = []
    @Published var comments: [Comment] = []
    @Published var userVotes: [UUID: VoteDirection] = [:]
    @Published var userCommentVotes: [UUID: VoteDirection] = [:]
    @Published var myPostIds: Set<UUID> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Set when Supabase session is restored (for "Message author" and message UI).
    @Published var currentUserId: UUID?
    
    /// Optional display name the user chose in their profile. Falls back to "Anónimo".
    @Published var displayName: String?
    /// Optional emoji the user chose as their avatar. Falls back to their campus short-name initial.
    @Published var userEmoji: String?
    /// Optional avatar background color name (e.g. "green", "blue"). Falls back to green.
    @Published var userAccentColor: String?
    
    @Published var conversations: [Conversation] = []
    @Published var messagesByConversation: [UUID: [PrivateMessage]] = [:]
    
    /// Poll vote counts per post. Key: postId, value: [optionIndex: count].
    @Published var pollVoteCounts: [UUID: [Int: Int]] = [:]
    /// Current user's poll vote per post. Key: postId, value: optionIndex.
    @Published var myPollVote: [UUID: Int] = [:]
    
    @Published var hasCompletedWalkthrough: Bool = false
    private static let hasCompletedWalkthroughKey = "ECHO_hasCompletedWalkthrough"
    
    /// True after the user has seen the small "tap to comment / vote" tooltip on the first post.
    @Published var hasSeenFirstPostTooltip: Bool = false
    private static let hasSeenFirstPostTooltipKey = "ECHO_hasSeenFirstPostTooltip"
    
    // MARK: - Tab + nav paths (so push notifications can deep-link)
    @Published var selectedTab: Int = 0
    /// Heterogeneous: holds Post (post detail) and HashtagRoute (hashtag feed) values.
    @Published var feedPath: NavigationPath = NavigationPath()
    @Published var messagesPath: NavigationPath = NavigationPath()
    
    // MARK: - Reactions (🔥 😂 💯)
    /// Counts per post: [postId: [type: count]].
    @Published var postReactionCounts: [UUID: [PostReactionType: Int]] = [:]
    /// Reaction types the user has used today (UTC). Disables those buttons app-wide.
    @Published var myReactionsToday: Set<PostReactionType> = []
    
    // MARK: - Search results
    @Published var searchResults: [Post] = []
    @Published var isSearching: Bool = false
    
    // MARK: - Hashtag feed (when viewing a single tag)
    @Published var hashtagFeed: [Post] = []
    @Published var hashtagFeedTag: String?
    @Published var trendingTags: [(tag: String, count: Int)] = []

    // MARK: - Referrals ("Invita y Gana" — evento regreso a clases)
    /// Prize ladder: 1 → OG badge (exclusive 🐿️ avatar) · 5 → gold profile color ·
    /// every `referralsPerDrink` → Starbucks/Tim Hortons drink (repeatable, no cap).
    /// Keep `referralsPerDrink` in sync with app_config.referrals_per_drink.
    static let referralOGBadgeAt = 1
    static let referralGoldProfileAt = 5
    static let referralsPerDrink = 10
    /// My permanent 6-char invite code.
    @Published var referralCode: String?
    /// Referrals I made (pending = friend signed up flow started, completed = friend posted).
    @Published var myReferrals: [Referral] = []
    /// Drinks I've earned (1 per `referralsPerDrink` completed, unlimited).
    @Published var myReferralRewards: [ReferralReward] = []
    /// The referral where I'm the invited user (nil = never entered a code).
    @Published var myReferralClaim: Referral?
    /// True right after a fresh signup — show the "¿Quién te invitó?" sheet once.
    @Published var shouldOfferReferralClaim = false
    /// Code prefilled from an invite link (https://…/i/CODE).
    @Published var pendingInviteCode: String?
    private static let referralPromptSeenKey = "ECHO_referralPromptSeen"

    var completedReferralCount: Int { myReferrals.filter { $0.status == .completed }.count }
    var pendingReferralCount: Int { myReferrals.filter { $0.status == .pending }.count }
    /// Digital unlocks derived from completed referrals.
    var hasOGBadge: Bool { completedReferralCount >= Self.referralOGBadgeAt }
    var hasGoldProfile: Bool { completedReferralCount >= Self.referralGoldProfileAt }
    /// Drinks earned so far (1 per `referralsPerDrink`, unlimited).
    var referralDrinksEarned: Int { completedReferralCount / Self.referralsPerDrink }
    /// Progress inside the current drink cycle (0..<referralsPerDrink).
    var referralDrinkProgress: Int { completedReferralCount % Self.referralsPerDrink }
    
    static let downvoteHideThreshold = 5
    
    var userKarma: Int {
        if useSupabase {
            return _cachedKarma
        }
        let postKarma = posts.filter { myPostIds.contains($0.id) }.reduce(0) { $0 + $1.score }
        let commentKarma = comments.reduce(0) { $0 + $1.score }
        return postKarma + commentKarma
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
        self.hasCompletedWalkthrough = UserDefaults.standard.bool(forKey: Self.hasCompletedWalkthroughKey)
        self.hasSeenFirstPostTooltip = UserDefaults.standard.bool(forKey: Self.hasSeenFirstPostTooltipKey)
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
        guard !isPerformingLogin else { return }
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
            displayName = nil
            userEmoji = nil
            userAccentColor = nil
            return
        }
        verifiedCampus = campus
        selectedCampus = campus
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        currentUserId = await auth.getCurrentUserId()
        displayName = profile.displayName
        userEmoji = profile.emoji
        userAccentColor = profile.accentColor
        await loadPosts()
        await loadKarma()
        await loadConversations()
        await registerPushNotificationsIfNeeded()
        await uploadDeviceTokenIfNeeded()
        await loadReferralData()
        await evaluateReferralClaimPrompt()
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
        var list = posts.filter { $0.campusId == campusId }
        if feedSort == .hot {
            list = list.filter { $0.createdAt >= twoDaysAgo }
        }
        return list.sorted { p1, p2 in
            if p1.isPinned != p2.isPinned { return p1.isPinned }
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
    /// All state flips happen atomically in a single MainActor.run so the view tree rebuilds only once
    /// (prevents visible flash back to campus-selection step during the Onboarding → ContentView transition).
    func enterWithEmailOTP(campus: Campus, email: String, code: String) async throws {
        guard let auth = authService else {
            completeOnboarding(verifiedCampus: campus)
            return
        }
        await MainActor.run { isPerformingLogin = true }
        defer { Task { @MainActor [weak self] in self?.isPerformingLogin = false } }
        try await auth.verifyOTP(email: email, code: code, campusId: campus.id)
        guard let uid = await auth.getCurrentUserId() else { throw EchoError.notAuthenticated }
        try await auth.createProfile(userId: uid, campusId: campus.id)
        let existingProfile = try? await auth.fetchProfile()
        await MainActor.run {
            verifiedCampus = campus
            selectedCampus = campus
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
            requiresReauthAfterSignOut = false
            UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
            currentUserId = uid
            displayName = existingProfile?.displayName
            userEmoji = existingProfile?.emoji
            userAccentColor = existingProfile?.accentColor
        }
        await loadPosts()
        await loadMyVotes()
        await loadKarma()
        await loadConversations()
        await registerPushNotificationsIfNeeded()
        await uploadDeviceTokenIfNeeded()
        await loadReferralData()
        await evaluateReferralClaimPrompt()
    }

    /// Kept for backward compatibility / edge cases where onboarding needs to finish separately from auth.
    @MainActor
    func finalizeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        requiresReauthAfterSignOut = false
        UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
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
            isPerformingLogin = true
            defer { isPerformingLogin = false }
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
                await loadReferralData()
                await evaluateReferralClaimPrompt()
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
            hasCompletedWalkthrough = false
            UserDefaults.standard.set(false, forKey: Self.hasCompletedWalkthroughKey)
            verifiedCampus = nil
            selectedCampus = Campus.mexicanUniversities[0]
            isReviewerSession = false
            posts = []
            comments = []
            userVotes = [:]
            userCommentVotes = [:]
            myPostIds = []
            _cachedKarma = 0
            currentUserId = nil
            displayName = nil
            userEmoji = nil
            userAccentColor = nil
            conversations = []
            messagesByConversation = [:]
            referralCode = nil
            myReferrals = []
            myReferralRewards = []
            myReferralClaim = nil
            shouldOfferReferralClaim = false
            pendingInviteCode = nil
        }
        if let auth = auth {
            try await auth.signOut()
        }
    }
    
    /// Update the user's custom display name, emoji, and accent color (nil values clear them). Reviewer sessions update only local state.
    func updateProfileDisplay(displayName newName: String?, emoji newEmoji: String?, accentColor newColor: String?) async throws {
        let trimmedName = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedName?.isEmpty ?? true) ? nil : trimmedName
        let finalEmoji = (newEmoji?.isEmpty ?? true) ? nil : newEmoji
        let finalColor = (newColor?.isEmpty ?? true) ? nil : newColor
        
        if let auth = authService, !isReviewerSession {
            try await auth.updateProfileDisplay(displayName: finalName, emoji: finalEmoji, accentColor: finalColor)
        }
        await MainActor.run {
            self.displayName = finalName
            self.userEmoji = finalEmoji
            self.userAccentColor = finalColor
        }
    }
    
    // MARK: - Load from Supabase
    @MainActor
    func loadPosts() async {
        guard let db = databaseService, let campusId = verifiedCampus?.id else { return }
        isLoading = true
        do {
            let rows = try await db.fetchPosts(campusId: campusId, sortHot: feedSort == .hot)
            let newPosts = rows.map { $0.toPost() }
            posts = newPosts
            isLoading = false
            await loadMyVotes()
            await loadPollData()
            await loadKarma()
            await loadReactionCounts(for: newPosts.map(\.id))
            await loadMyReactionsToday()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
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
            await loadMyCommentVotes(for: newComments.map(\.id))
        } catch { }
    }
    
    private func loadMyCommentVotes(for commentIds: [UUID]) async {
        guard let db = databaseService, !commentIds.isEmpty else { return }
        do {
            let map = try await db.fetchMyCommentVotes(commentIds: commentIds)
            await MainActor.run {
                for (id, dir) in map {
                    userCommentVotes[id] = VoteDirection(rawValue: dir) ?? .none
                }
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
        guard !isReviewerSession, let db = databaseService else { return }
        do {
            let rows = try await db.fetchMyConversations()
            var convs = rows.map { $0.toConversation() }
            // Enrich with the latest message so the list shows a preview and sorts by activity.
            if let latest = try? await db.fetchLatestMessages(conversationIds: convs.map(\.id)) {
                for i in convs.indices {
                    if let msg = latest[convs[i].id] {
                        convs[i].lastMessageAt = msg.createdAt
                        convs[i].lastMessageBody = msg.body
                    }
                }
            }
            convs.sort { ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt) }
            let sorted = convs
            await MainActor.run { conversations = sorted }
        } catch { }
    }
    
    func loadMessages(conversationId: UUID) async {
        guard !isReviewerSession, let db = databaseService else { return }
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
    
    /// Find or create a conversation to message the author of a specific comment.
    func getOrCreateConversationForComment(postId: UUID, commentAuthorId: UUID, commentId: UUID) async throws -> Conversation {
        guard let db = databaseService else { throw EchoError.supabaseNotConfigured }
        let row = try await db.getOrCreateConversationFromComment(postId: postId, commentAuthorId: commentAuthorId, commentId: commentId)
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

    // MARK: - Referrals ("Invita y Gana")

    /// Load my code, my referrals, my rewards, and whether I already claimed someone's code.
    /// Fails silently (e.g. if migration 014 isn't applied yet) so it never blocks login.
    func loadReferralData() async {
        guard !isReviewerSession, let db = databaseService else { return }
        if let code = try? await db.ensureReferralCode() {
            await MainActor.run { referralCode = code }
        }
        if let rows = try? await db.fetchMyReferrals() {
            await MainActor.run { myReferrals = rows.map { $0.toReferral() } }
        }
        if let rewards = try? await db.fetchMyReferralRewards() {
            await MainActor.run { myReferralRewards = rewards.map { $0.toReferralReward() } }
        }
        do {
            let claim = try await db.fetchMyReferralClaim()
            await MainActor.run { myReferralClaim = claim?.toReferral() }
        } catch { }
    }

    /// Submit a friend's code. Returns the server status (nil on network error).
    func claimReferralCode(_ code: String) async -> ReferralClaimStatus? {
        guard let db = databaseService else { return nil }
        do {
            let status = try await db.claimReferral(code: code)
            if status == .ok, let claim = try? await db.fetchMyReferralClaim() {
                await MainActor.run {
                    myReferralClaim = claim.toReferral()
                    pendingInviteCode = nil
                }
            }
            return status
        } catch {
            return nil
        }
    }

    /// Show the "¿Quién te invitó?" prompt only for fresh accounts (< 7 days, matches the
    /// server rule), only once, and only if they haven't claimed a code yet.
    private func evaluateReferralClaimPrompt() async {
        guard useSupabase, !isReviewerSession else { return }
        guard !UserDefaults.standard.bool(forKey: Self.referralPromptSeenKey) else { return }
        guard myReferralClaim == nil else { return }
        guard let created = await authService?.getCurrentUserCreatedAt(),
              Date().timeIntervalSince(created) < 7 * 24 * 3600 else { return }
        await MainActor.run { shouldOfferReferralClaim = true }
    }

    func markReferralPromptSeen() {
        shouldOfferReferralClaim = false
        UserDefaults.standard.set(true, forKey: Self.referralPromptSeenKey)
    }

    /// Handle `https://…/i/<code>` invite links: prefill the code and re-offer the claim
    /// sheet (server still validates account age / duplicates).
    func handleInviteLinkURL(_ url: URL) -> Bool {
        guard let code = ShareLinks.inviteCode(from: url) else { return false }
        pendingInviteCode = code
        if myReferralClaim == nil {
            shouldOfferReferralClaim = true
        }
        return true
    }

    // MARK: - Actions
    func completeWalkthrough() {
        hasCompletedWalkthrough = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedWalkthroughKey)
    }
    
    func completeOnboarding(verifiedCampus: Campus) {
        self.verifiedCampus = verifiedCampus
        self.selectedCampus = verifiedCampus
        self.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        requiresReauthAfterSignOut = false
        UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
    }
    
    /// Completes onboarding for reviewers / devs (review@echoiosone.com + 123456); bypasses OTP but creates a real Supabase session (email+password → signUp → anonymous fallback).
    @MainActor
    func completeReviewerOnboarding(campus: Campus) async {
        isReviewerSession = true
        isPerformingLogin = true
        defer { isPerformingLogin = false }
        
        verifiedCampus = campus
        selectedCampus = campus
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        requiresReauthAfterSignOut = false
        UserDefaults.standard.set(false, forKey: Self.requiresReauthAfterSignOutKey)
        
        if let auth = authService {
            let email = SupabaseConfig.reviewerEmail ?? "review@echoiosone.com"
            let password = "EchoReview_\(SupabaseConfig.reviewerCode)!"
            
            do {
                try await auth.signInWithPassword(email: email, password: password)
            } catch {
                do {
                    try await auth.signUpWithPassword(email: email, password: password)
                } catch {
                    try? await auth.signInAnonymously()
                }
            }
            
            if let uid = await auth.getCurrentUserId() {
                try? await auth.createProfile(userId: uid, campusId: campus.id)
                currentUserId = uid
            }
        }
        
        await loadPosts()
        await loadKarma()
        await loadConversations()
        
        injectReviewerMockMessages()
    }
    
    private func injectReviewerMockMessages() {
        let me = currentUserId ?? UUID()
        if currentUserId == nil { currentUserId = me }
        
        let otherA = UUID()
        let otherB = UUID()
        let cA = UUID()
        let cB = UUID()
        let now = Date()
        
        conversations = [
            Conversation(id: cA, postId: UUID(),
                         postBodySnippet: "Alguien más tiene final de Cálculo mañana?",
                         postAuthorId: otherA, initiatorId: me,
                         createdAt: now.addingTimeInterval(-3600),
                         lastMessageAt: now.addingTimeInterval(-600),
                         lastMessageBody: "Los de integrales dobles porfa"),
            Conversation(id: cB, postId: UUID(),
                         postBodySnippet: "Se busca equipo para hackathon este fin",
                         postAuthorId: otherB, initiatorId: me,
                         createdAt: now.addingTimeInterval(-7200),
                         lastMessageAt: now.addingTimeInterval(-1800),
                         lastMessageBody: "Perfecto, yo estudio diseño")
        ]
        
        messagesByConversation[cA] = [
            PrivateMessage(id: UUID(), conversationId: cA, senderId: me,
                           body: "Oye, tienes los apuntes del parcial 2?", createdAt: now.addingTimeInterval(-3500)),
            PrivateMessage(id: UUID(), conversationId: cA, senderId: otherA,
                           body: "Sí! Te los paso. Cuáles necesitas?", createdAt: now.addingTimeInterval(-3000)),
            PrivateMessage(id: UUID(), conversationId: cA, senderId: me,
                           body: "Los de integrales dobles porfa", createdAt: now.addingTimeInterval(-600)),
        ]
        
        messagesByConversation[cB] = [
            PrivateMessage(id: UUID(), conversationId: cB, senderId: me,
                           body: "Hola! Vi tu post, aún hay lugar?", createdAt: now.addingTimeInterval(-7000)),
            PrivateMessage(id: UUID(), conversationId: cB, senderId: otherB,
                           body: "Sí! Somos 3, nos falta alguien de diseño", createdAt: now.addingTimeInterval(-5400)),
            PrivateMessage(id: UUID(), conversationId: cB, senderId: otherB,
                           body: "Perfecto, yo estudio diseño", createdAt: now.addingTimeInterval(-1800)),
        ]
    }
    
    /// Add a post. When using Supabase, inserts into DB. Use `addPostAsync` from UI to await and show errors.
    func addPost(_ body: String, imageData: Data? = nil, imageFileExtension: String = "jpg", poll: Poll? = nil) {
        let text = String(body.prefix(Post.maxLength))
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = userEmoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = userAccentColor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorName: String? = (name?.isEmpty ?? true) ? nil : name
        let authorEmoji: String? = (emoji?.isEmpty ?? true) ? nil : emoji
        let authorColor: String? = (color?.isEmpty ?? true) ? nil : color
        
        if let db = databaseService {
            Task {
                do {
                    var imageURL: String? = nil
                    if let data = imageData {
                        imageURL = try await db.uploadPostImage(data: data, fileExtension: imageFileExtension)
                    }
                    let row = try await db.insertPost(body: text, campusId: selectedCampus.id, imageURL: imageURL, pollQuestion: poll?.question, pollOptions: poll?.options, authorDisplayName: authorName, authorEmoji: authorEmoji, authorAccentColor: authorColor)
                    await MainActor.run {
                        var newPost = row.toPost()
                        // Trigger `tr_post_author_self_upvote` already inserted the vote server-side;
                        // reflect it locally so the UI shows score 1 and the up arrow highlighted.
                        if newPost.authorId != nil { newPost.score = max(newPost.score, 1) }
                        posts.insert(newPost, at: 0)
                        myPostIds.insert(row.id)
                        if newPost.authorId != nil { userVotes[row.id] = .up }
                        Haptics.postPublished()
                    }
                    await loadPollData()
                    await loadKarma()
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        } else {
            let post = Post(body: text, score: 1, campusId: selectedCampus.id, authorDisplayName: authorName, authorEmoji: authorEmoji, authorAccentColor: authorColor, poll: poll)
            posts.insert(post, at: 0)
            myPostIds.insert(post.id)
            userVotes[post.id] = .up
            Haptics.postPublished()
        }
    }
    
    /// Call from UI to post and await result; throws on failure so you can show error and only dismiss on success.
    func addPostAsync(_ body: String, imageData: Data? = nil, imageFileExtension: String = "jpg", poll: Poll? = nil) async throws {
        let text = String(body.prefix(Post.maxLength))
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = userEmoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = userAccentColor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorName: String? = (name?.isEmpty ?? true) ? nil : name
        let authorEmoji: String? = (emoji?.isEmpty ?? true) ? nil : emoji
        let authorColor: String? = (color?.isEmpty ?? true) ? nil : color
        
        if let db = databaseService {
            var imageURL: String? = nil
            if let data = imageData {
                imageURL = try await db.uploadPostImage(data: data, fileExtension: imageFileExtension)
            }
            let row = try await db.insertPost(body: text, campusId: selectedCampus.id, imageURL: imageURL, pollQuestion: poll?.question, pollOptions: poll?.options, authorDisplayName: authorName, authorEmoji: authorEmoji, authorAccentColor: authorColor)
            await MainActor.run {
                var newPost = row.toPost()
                if newPost.authorId != nil { newPost.score = max(newPost.score, 1) }
                posts.insert(newPost, at: 0)
                myPostIds.insert(row.id)
                if newPost.authorId != nil { userVotes[row.id] = .up }
                Haptics.postPublished()
            }
            await loadPollData()
            await loadKarma()
        } else {
            let post = Post(body: text, score: 1, campusId: selectedCampus.id, authorDisplayName: authorName, authorEmoji: authorEmoji, authorAccentColor: authorColor, poll: poll)
            await MainActor.run {
                posts.insert(post, at: 0)
                myPostIds.insert(post.id)
                userVotes[post.id] = .up
                Haptics.postPublished()
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
    
    func addComment(_ body: String, postId: UUID, parentCommentId: UUID? = nil) {
        Haptics.voteTick()
        if let db = databaseService {
            Task {
                do {
                    let row = try await db.insertComment(postId: postId, body: body, parentCommentId: parentCommentId)
                    let newComment = row.toComment()
                    await MainActor.run {
                        comments.append(newComment)
                        if let i = posts.firstIndex(where: { $0.id == postId }) {
                            posts[i].commentCount += 1
                        }
                        userCommentVotes[newComment.id] = .up
                    }
                    try? await db.setCommentVote(commentId: newComment.id, direction: 1)
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
        } else {
            let comment = Comment(body: body, postId: postId, parentCommentId: parentCommentId)
            comments.append(comment)
            userCommentVotes[comment.id] = .up
            if let i = posts.firstIndex(where: { $0.id == postId }) {
                posts[i].commentCount += 1
            }
        }
    }
    
    func vote(postId: UUID, direction: VoteDirection) {
        if direction == .up || direction == .down { Haptics.voteTick() }
        guard let i = posts.firstIndex(where: { $0.id == postId }) else { return }
        let prev = userVotes[postId] ?? .none
        let delta = direction.rawValue - prev.rawValue
        // Optimistic: update locally right away (no full feed reload / scroll jump).
        posts[i].score += delta
        if direction == .none { userVotes.removeValue(forKey: postId) }
        else { userVotes[postId] = direction }
        guard let db = databaseService else { return }
        Task {
            do {
                try await db.setVote(postId: postId, direction: direction.rawValue)
                await loadKarma()
            } catch {
                await MainActor.run {
                    // Revert on failure.
                    if let j = posts.firstIndex(where: { $0.id == postId }) {
                        posts[j].score -= delta
                    }
                    if prev == .none { userVotes.removeValue(forKey: postId) }
                    else { userVotes[postId] = prev }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func userVote(for postId: UUID) -> VoteDirection {
        userVotes[postId] ?? .none
    }
    
    func voteComment(commentId: UUID, direction: VoteDirection) {
        if direction == .up || direction == .down { Haptics.voteTick() }
        guard let i = comments.firstIndex(where: { $0.id == commentId }) else { return }
        let prev = userCommentVotes[commentId] ?? .none
        let delta = direction.rawValue - prev.rawValue
        // Optimistic local update (no comment-list reload).
        comments[i].score += delta
        if direction == .none { userCommentVotes.removeValue(forKey: commentId) }
        else { userCommentVotes[commentId] = direction }
        guard let db = databaseService else { return }
        Task {
            do {
                try await db.setCommentVote(commentId: commentId, direction: direction.rawValue)
                await loadKarma()
            } catch {
                await MainActor.run {
                    if let j = comments.firstIndex(where: { $0.id == commentId }) {
                        comments[j].score -= delta
                    }
                    if prev == .none { userCommentVotes.removeValue(forKey: commentId) }
                    else { userCommentVotes[commentId] = prev }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func userCommentVote(for commentId: UUID) -> VoteDirection {
        userCommentVotes[commentId] ?? .none
    }
    
    // MARK: - Threaded comments helpers
    
    /// Top-level comments for a post (those that are not replies). Sorted oldest-first to match Yik Yak / chronological feel.
    func topLevelComments(for postId: UUID) -> [Comment] {
        comments
            .filter { $0.postId == postId && $0.parentCommentId == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    /// Replies to a given parent comment, oldest first.
    func replies(for parentId: UUID) -> [Comment] {
        comments
            .filter { $0.parentCommentId == parentId }
            .sorted { $0.createdAt < $1.createdAt }
    }
    
    // MARK: - Reactions
    
    func reactionCount(for postId: UUID, type: PostReactionType) -> Int {
        postReactionCounts[postId]?[type] ?? 0
    }
    
    func canReactToday(_ type: PostReactionType) -> Bool {
        !myReactionsToday.contains(type)
    }
    
    func react(postId: UUID, type: PostReactionType) {
        guard !myReactionsToday.contains(type) else { return }
        // Optimistic UI update
        postReactionCounts[postId, default: [:]][type, default: 0] += 1
        myReactionsToday.insert(type)
        Haptics.voteTick()
        guard let db = databaseService else { return }
        Task {
            do {
                try await db.addPostReaction(postId: postId, type: type)
            } catch {
                // Roll back if server rejected (likely the daily-unique constraint).
                await MainActor.run {
                    postReactionCounts[postId, default: [:]][type, default: 1] -= 1
                    if (postReactionCounts[postId]?[type] ?? 0) <= 0 {
                        postReactionCounts[postId]?[type] = nil
                    }
                    // Keep myReactionsToday so we don't spam retries; reload from server.
                }
                await loadMyReactionsToday()
            }
        }
    }
    
    func loadReactionCounts(for postIds: [UUID]) async {
        guard let db = databaseService, !postIds.isEmpty else { return }
        if let map = try? await db.fetchPostReactionCounts(postIds: postIds) {
            await MainActor.run {
                for (id, counts) in map { postReactionCounts[id] = counts }
            }
        }
    }
    
    func loadMyReactionsToday() async {
        guard let db = databaseService else { return }
        if let set = try? await db.fetchMyReactionsToday() {
            await MainActor.run { myReactionsToday = set }
        }
    }
    
    // MARK: - Reports
    
    @Published var reportedPostIds: Set<UUID> = []
    
    func reportPost(postId: UUID, reason: String? = nil) {
        guard let db = databaseService else { return }
        reportedPostIds.insert(postId)
        Task {
            try? await db.reportPost(postId: postId, reason: reason)
        }
    }
    
    func reportComment(commentId: UUID, reason: String? = nil) {
        guard let db = databaseService else { return }
        Task {
            try? await db.reportComment(commentId: commentId, reason: reason)
        }
    }
    
    // MARK: - Search
    
    func runSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let db = databaseService, let campusId = verifiedCampus?.id else {
            await MainActor.run { searchResults = []; isSearching = false }
            return
        }
        guard !trimmed.isEmpty else {
            await MainActor.run { searchResults = []; isSearching = false }
            return
        }
        await MainActor.run { isSearching = true }
        defer { Task { @MainActor in isSearching = false } }
        do {
            let rows = try await db.searchPosts(campusId: campusId, query: trimmed)
            await MainActor.run { searchResults = rows.map { $0.toPost() } }
        } catch {
            await MainActor.run { searchResults = []; errorMessage = error.localizedDescription }
        }
    }
    
    func clearSearch() {
        searchResults = []
        isSearching = false
    }
    
    // MARK: - Hashtag feed
    
    func loadHashtagFeed(_ tag: String) async {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let db = databaseService, let campusId = verifiedCampus?.id, !normalized.isEmpty else {
            await MainActor.run { hashtagFeed = []; hashtagFeedTag = nil }
            return
        }
        await MainActor.run { hashtagFeedTag = normalized }
        do {
            let rows = try await db.fetchPostsByTag(campusId: campusId, tag: normalized)
            await MainActor.run { hashtagFeed = rows.map { $0.toPost() } }
        } catch {
            await MainActor.run { hashtagFeed = []; errorMessage = error.localizedDescription }
        }
    }
    
    func loadTrendingTags() async {
        guard let db = databaseService, let campusId = verifiedCampus?.id else { return }
        if let tags = try? await db.fetchTrendingTags(campusId: campusId) {
            await MainActor.run { trendingTags = tags }
        }
    }
    
    /// Lightweight client-side hashtag detection for highlighting and tap-to-navigate.
    static func extractHashtags(from body: String) -> [String] {
        let pattern = "#([\\p{L}0-9_]{2,30})"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(body.startIndex..., in: body)
        return re.matches(in: body, range: range).compactMap { match -> String? in
            guard match.numberOfRanges >= 2, let r = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[r]).lowercased()
        }
    }
    
    // MARK: - Tooltip on first post
    
    func markFirstPostTooltipSeen() {
        hasSeenFirstPostTooltip = true
        UserDefaults.standard.set(true, forKey: Self.hasSeenFirstPostTooltipKey)
    }
    
    // MARK: - Deep link routing (push tap or echo:// URL)
    
    /// Parse OneSignal-style userInfo (which wraps app data under `custom.a`) or a flat dict, then route.
    func handlePushUserInfo(_ userInfo: [AnyHashable: Any]) {
        let aDict: [String: Any]
        if let custom = userInfo["custom"] as? [String: Any], let a = custom["a"] as? [String: Any] {
            aDict = a
        } else {
            var flat: [String: Any] = [:]
            for (k, v) in userInfo { if let s = k as? String { flat[s] = v } }
            aDict = flat
        }
        if let convStr = aDict["conversation_id"] as? String, let id = UUID(uuidString: convStr) {
            openConversation(id: id)
            return
        }
        if let postStr = aDict["post_id"] as? String, let id = UUID(uuidString: postStr) {
            openPost(id: id)
            return
        }
    }
    
    /// Handle `echo://post/<uuid>` deep links shared from inside the app.
    func handlePostDeepLinkURL(_ url: URL) -> Bool {
        guard url.scheme == "echo", url.host == "post" else { return false }
        let last = url.lastPathComponent
        guard let id = UUID(uuidString: last) else { return false }
        openPost(id: id)
        return true
    }
    
    /// Switch to feed tab and push the post detail. Fetches the post if not in memory.
    func openPost(id: UUID) {
        Task { @MainActor in
            if let p = posts.first(where: { $0.id == id }) {
                selectedTab = 0
                feedPath = NavigationPath()
                feedPath.append(p)
                return
            }
            guard let db = databaseService else { return }
            if let row = try? await db.fetchPost(id: id) {
                let p = row.toPost()
                if !posts.contains(where: { $0.id == p.id }) { posts.insert(p, at: 0) }
                selectedTab = 0
                feedPath = NavigationPath()
                feedPath.append(p)
            }
        }
    }
    
    /// Switch to messages tab and open the conversation.
    func openConversation(id: UUID) {
        Task { @MainActor in
            if let c = conversations.first(where: { $0.id == id }) {
                selectedTab = 1
                messagesPath = NavigationPath()
                messagesPath.append(c)
                return
            }
            await loadConversations()
            if let c = conversations.first(where: { $0.id == id }) {
                selectedTab = 1
                messagesPath = NavigationPath()
                messagesPath.append(c)
            }
        }
    }
}

/// Wrapper used as a `NavigationPath` value to push the hashtag feed.
struct HashtagRoute: Hashable {
    let tag: String
}
