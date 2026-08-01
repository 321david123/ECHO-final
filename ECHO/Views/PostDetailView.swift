//
//  PostDetailView.swift
//  ECHO
//

import SwiftUI

struct PostDetailView: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    @State private var commentText = ""
    @FocusState private var commentFocused: Bool
    @State private var messageConversation: Conversation?
    @State private var messageError: String?
    /// When non-nil, the input bar is in "reply mode" and submits a reply to this comment.
    @State private var replyingToCommentId: UUID? = nil
    @State private var replyingToIndex: Int? = nil
    @State private var showReported = false
    @State private var voteFloat: Int? = nil
    @State private var upJumpTrigger: Int = 0
    @State private var downJumpTrigger: Int = 0
    
    private var canMessageAuthor: Bool {
        guard let authorId = post.authorId, let me = appState.currentUserId else { return false }
        return authorId != me
    }
    
    private var postOrUpdated: Post {
        appState.posts.first(where: { $0.id == post.id }) ?? post
    }
    
    /// Top-level comments only; their replies are rendered nested in CommentRowView.
    private var topLevelComments: [Comment] {
        appState.topLevelComments(for: post.id)
    }
    
    private var hashtags: [String] {
        AppState.extractHashtags(from: postOrUpdated.body)
    }
    
    private var shareText: String {
        ShareLinks.text(for: postOrUpdated)
    }
    
    private var campusName: String {
        Campus.mexicanUniversities.first(where: { $0.id == post.campusId })?.shortName ?? "Campus"
    }
    
    private var authorName: String {
        let n = postOrUpdated.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "Anónimo" : n
    }
    private var authorAvatar: String {
        let e = postOrUpdated.authorEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return e.isEmpty ? "A" : e
    }
    private var avatarIsEmoji: Bool {
        let e = postOrUpdated.authorEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !e.isEmpty
    }
    private var avatarTint: Color {
        AccentColor.from(postOrUpdated.authorAccentColor).color
    }
    
    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604800 { return "\(s / 86400)d" }
        return "\(s / 604800)sem"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    postSection
                    commentsList
                }
            }
            .scrollDismissesKeyboard(.interactively)
            
            commentInputBar
        }
        .background(Color.echoBackground)
        .navigationTitle("ECHO")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if appState.useSupabase { Task { await appState.loadComments(for: post.id) } }
        }
        .sheet(item: $messageConversation) { conv in
            NavigationStack {
                ConversationThreadView(conversation: conv)
                    .environmentObject(appState)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cerrar") { messageConversation = nil }
                                .foregroundStyle(Color.echoGreen)
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if showReported {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Reportado")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.echoGreen)
                .clipShape(Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 50)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showReported = false }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showReported)
    }
    
    // MARK: - Post section
    
    private var postSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Author row
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(avatarTint.opacity(0.35))
                        .frame(width: 40, height: 40)
                    Text(authorAvatar)
                        .font(avatarIsEmoji ? .system(size: 22) : .body.weight(.bold))
                        .foregroundStyle(avatarIsEmoji ? Color.echoText : avatarTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(authorName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.echoText)
                    Text(campusName)
                        .font(.subheadline)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                Spacer(minLength: 0)
                if postOrUpdated.isPinned {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                        Text("Aviso")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.echoGreen)
                }
                Text(relativeTime(postOrUpdated.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(Color.echoTextTertiary)
                Menu {
                    Button(role: .destructive) {
                        appState.reportPost(postId: post.id)
                        showReported = true
                    } label: {
                        Label("Reportar", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.echoTextSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Post body
            Text(postOrUpdated.body)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.echoText)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            
            // Image
            if let urlString = postOrUpdated.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(Color.echoTextTertiary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 12)
            }
            
            // Poll
            if let poll = postOrUpdated.poll {
                pollSection(poll)
                    .padding(.bottom, 12)
            }
            
            // Hashtag chips (tappable to navigate to hashtag feed)
            if !hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(hashtags, id: \.self) { tag in
                            Button {
                                Task {
                                    await appState.loadHashtagFeed(tag)
                                    await MainActor.run {
                                        appState.selectedTab = 0
                                        appState.feedPath.append(HashtagRoute(tag: tag))
                                    }
                                }
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.echoGreen)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.echoGreen.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            
            // Action bar
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.body)
                    Text("\(postOrUpdated.commentCount)")
                        .font(.body)
                }
                .foregroundStyle(Color.echoTextSecondary)
                
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                .buttonStyle(.plain)
                
                if canMessageAuthor {
                    Button {
                        Task {
                            messageError = nil
                            guard let authorId = post.authorId else { return }
                            do {
                                let conv = try await appState.getOrCreateConversation(postId: post.id, postAuthorId: authorId)
                                messageConversation = conv
                            } catch {
                                messageError = error.localizedDescription
                            }
                        }
                    } label: {
                        Image(systemName: "paperplane")
                            .font(.body)
                            .foregroundStyle(Color.echoTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer(minLength: 0)
                
                if !postOrUpdated.isPinned {
                    let myVote = appState.userVote(for: post.id)
                    HStack(spacing: 8) {
                        Button {
                            let next: VoteDirection = myVote == .up ? .none : .up
                            appState.vote(postId: post.id, direction: next)
                            triggerVoteFloat(prev: myVote, next: next)
                            upJumpTrigger &+= 1
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(myVote == .up ? Color.echoGreen : Color.echoTextSecondary)
                                .modifier(ArrowJump(direction: .up, trigger: upJumpTrigger))
                                .frame(width: 34, height: 34)
                                .background(Color.echoVoteCircle)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        ZStack {
                            Text("\(postOrUpdated.score)")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.echoGreen)
                                .frame(minWidth: 28, alignment: .center)
                                .contentTransition(.numericText(value: Double(postOrUpdated.score)))
                                .animation(.snappy(duration: 0.12), value: postOrUpdated.score)
                            
                            if let delta = voteFloat {
                                FloatingDeltaLabel(delta: delta)
                            }
                        }
                        
                        Button {
                            let next: VoteDirection = myVote == .down ? .none : .down
                            appState.vote(postId: post.id, direction: next)
                            triggerVoteFloat(prev: myVote, next: next)
                            downJumpTrigger &+= 1
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(myVote == .down ? Color.echoOrange : Color.echoTextSecondary)
                                .modifier(ArrowJump(direction: .down, trigger: downJumpTrigger))
                                .frame(width: 34, height: 34)
                                .background(Color.echoVoteCircle)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 14)
            
            if let err = messageError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color.echoOrange)
                    .padding(.bottom, 8)
            }
            
            Rectangle()
                .fill(Color.echoSeparator.opacity(0.5))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Comments
    
    @ViewBuilder
    private var commentsList: some View {
        ForEach(Array(topLevelComments.enumerated()), id: \.element.id) { index, comment in
            commentBlock(comment: comment, displayIndex: index + 1)
        }
    }
    
    @ViewBuilder
    private func commentBlock(comment: Comment, displayIndex: Int) -> some View {
        let canMessageCommenter: Bool = {
            guard let me = appState.currentUserId, let cid = comment.authorId else { return false }
            return cid != me
        }()
        VStack(spacing: 0) {
            CommentRowView(
                comment: comment,
                index: displayIndex,
                indented: false,
                vote: appState.userCommentVote(for: comment.id),
                onVote: { direction in appState.voteComment(commentId: comment.id, direction: direction) },
                onReply: {
                    replyingToCommentId = comment.id
                    replyingToIndex = displayIndex
                    commentFocused = true
                },
                onMessage: canMessageCommenter ? {
                    Task {
                        messageError = nil
                        guard let cid = comment.authorId else { return }
                        do {
                            let conv = try await appState.getOrCreateConversationForComment(postId: post.id, commentAuthorId: cid, commentId: comment.id)
                            messageConversation = conv
                        } catch {
                            messageError = error.localizedDescription
                        }
                    }
                } : nil
            )
            // Replies (one level)
            ForEach(appState.replies(for: comment.id)) { reply in
                let canMessageReplier: Bool = {
                    guard let me = appState.currentUserId, let rid = reply.authorId else { return false }
                    return rid != me
                }()
                CommentRowView(
                    comment: reply,
                    index: displayIndex,
                    indented: true,
                    vote: appState.userCommentVote(for: reply.id),
                    onVote: { direction in appState.voteComment(commentId: reply.id, direction: direction) },
                    onReply: nil, // one level only
                    onMessage: canMessageReplier ? {
                        Task {
                            messageError = nil
                            guard let rid = reply.authorId else { return }
                            do {
                                let conv = try await appState.getOrCreateConversationForComment(postId: post.id, commentAuthorId: rid, commentId: reply.id)
                                messageConversation = conv
                            } catch {
                                messageError = error.localizedDescription
                            }
                        }
                    } : nil
                )
            }
        }
    }
    
    // MARK: - Comment input bar
    
    @ViewBuilder
    private var commentInputBar: some View {
        VStack(spacing: 0) {
            if replyingToCommentId != nil {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption)
                        .foregroundStyle(Color.echoGreen)
                    Text("Respondiendo a #\(replyingToIndex ?? 0)")
                        .font(.caption)
                        .foregroundStyle(Color.echoTextSecondary)
                    Spacer(minLength: 0)
                    Button {
                        replyingToCommentId = nil
                        replyingToIndex = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.echoTextTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            
            HStack(spacing: 10) {
                TextField(replyingToCommentId == nil ? "Escribe un comentario..." : "Escribe tu respuesta...", text: $commentText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($commentFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.echoCard)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                Button {
                    submitComment()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.echoTextTertiary : Color.echoGreen)
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.echoBar)
    }
    
    // MARK: - Poll
    
    private func pollSection(_ poll: Poll) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(poll.question)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.echoText)
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, optionText in
                let count = appState.pollVoteCount(for: post.id, optionIndex: index)
                let total = poll.options.indices.reduce(0) { appState.pollVoteCount(for: post.id, optionIndex: $1) + $0 }
                let fraction = total > 0 ? Double(count) / Double(total) : 0.0
                let isSelected = appState.myPollVote(for: post.id) == index
                Button {
                    appState.votePoll(postId: post.id, optionIndex: index)
                } label: {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.echoCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.echoGreen.opacity(0.25))
                                    .frame(maxWidth: .infinity)
                                    .scaleEffect(x: fraction, y: 1, anchor: .leading)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.echoGreen : Color.echoSeparator, lineWidth: isSelected ? 2 : 1)
                            )
                        HStack(spacing: 8) {
                            Text(optionText)
                                .font(.subheadline)
                                .foregroundStyle(Color.echoText)
                            Spacer(minLength: 0)
                            if appState.myPollVote(for: post.id) != nil {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(Color.echoTextTertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .buttonStyle(.plain)
                .disabled(appState.myPollVote(for: post.id) != nil)
            }
        }
    }
    
    private func submitComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addComment(trimmed, postId: post.id, parentCommentId: replyingToCommentId)
        commentText = ""
        replyingToCommentId = nil
        replyingToIndex = nil
    }
    
    private func triggerVoteFloat(prev: VoteDirection, next: VoteDirection) {
        let delta = next.rawValue - prev.rawValue
        guard delta != 0 else { return }
        voteFloat = delta
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            voteFloat = nil
        }
    }
}

// MARK: - Comment row (Yik Yak style)

private struct CommentRowView: View {
    let comment: Comment
    let index: Int
    /// When true, this is a reply (rendered indented under its parent).
    var indented: Bool = false
    let vote: VoteDirection
    let onVote: (VoteDirection) -> Void
    /// When non-nil, a "Responder" button appears.
    var onReply: (() -> Void)? = nil
    /// When non-nil, a paper-plane button appears to start a DM with the commenter.
    var onMessage: (() -> Void)? = nil
    @State private var upJumpTrigger: Int = 0
    @State private var downJumpTrigger: Int = 0
    
    private static let avatarColors: [Color] = [
        Color(red: 0.55, green: 0.35, blue: 0.85),  // purple
        Color(red: 0.20, green: 0.65, blue: 0.75),   // teal
        Color(red: 0.85, green: 0.50, blue: 0.25),   // orange
        Color(red: 0.30, green: 0.70, blue: 0.40),   // green
        Color(red: 0.80, green: 0.35, blue: 0.55),   // pink
        Color(red: 0.40, green: 0.55, blue: 0.85),   // blue
        Color(red: 0.75, green: 0.65, blue: 0.25),   // gold
    ]
    
    private var avatarColor: Color {
        Self.avatarColors[(index - 1) % Self.avatarColors.count]
    }
    
    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604800 { return "\(s / 86400)d" }
        return "\(s / 604800)sem"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(avatarColor.opacity(0.3))
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 12, height: 12)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // Header: #N · time (or reply icon for indented)
                    HStack(spacing: 6) {
                        if indented {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                        Text(indented ? "respuesta a #\(index)" : "#\(index)")
                            .font(.subheadline)
                            .fontWeight(indented ? .regular : .semibold)
                            .foregroundStyle(indented ? Color.echoTextSecondary : Color.echoText)
                        Text(relativeTime(comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(Color.echoTextTertiary)
                    }
                    
                    // Body
                    Text(comment.body)
                        .font(.body)
                        .foregroundStyle(Color.echoText)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 14) {
                        if let onReply = onReply {
                            Button(action: onReply) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrowshape.turn.up.left")
                                        .font(.caption)
                                    Text("Responder")
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.echoTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        if let onMessage = onMessage {
                            Button(action: onMessage) {
                                HStack(spacing: 4) {
                                    Image(systemName: "paperplane")
                                        .font(.caption)
                                    Text("Mensaje")
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.echoTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
                
                Spacer(minLength: 0)
                
                // Vote buttons
                VStack(spacing: 4) {
                    Button {
                        onVote(vote == .up ? .none : .up)
                        upJumpTrigger &+= 1
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(vote == .up ? Color.echoGreen : Color.echoTextTertiary)
                            .modifier(ArrowJump(direction: .up, trigger: upJumpTrigger))
                            .frame(width: 30, height: 30)
                            .background(Color.echoVoteCircle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(comment.score)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.echoGreen)
                        .frame(minWidth: 20, alignment: .center)
                        .contentTransition(.numericText(value: Double(comment.score)))
                        .animation(.snappy(duration: 0.12), value: comment.score)
                    
                    Button {
                        onVote(vote == .down ? .none : .down)
                        downJumpTrigger &+= 1
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(vote == .down ? Color.echoOrange : Color.echoTextTertiary)
                            .modifier(ArrowJump(direction: .down, trigger: downJumpTrigger))
                            .frame(width: 30, height: 30)
                            .background(Color.echoVoteCircle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, indented ? 44 : 16)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            
            Rectangle()
                .fill(Color.echoSeparator.opacity(0.3))
                .frame(height: 1)
                .padding(.leading, indented ? 92 : 64)
        }
    }
}

#Preview {
    NavigationStack {
        PostDetailView(post: Post(body: "Alguien más tiene final mañana?", score: 42, commentCount: 2, campusId: "tec-monterrey"))
            .environmentObject(AppState())
    }
}
