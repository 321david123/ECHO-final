//
//  PostRowView.swift
//  ECHO
//

import SwiftUI

struct PostRowView: View {
    @EnvironmentObject var appState: AppState
    let post: Post
    let campusName: String
    let vote: VoteDirection
    let onVote: (VoteDirection) -> Void
    var pollVoteCounts: [Int: Int] = [:]
    var myPollVote: Int? = nil
    var onPollVote: ((Int) -> Void)? = nil
    /// Tapping a hashtag chip navigates to the hashtag feed (handled by parent).
    var onTapHashtag: ((String) -> Void)? = nil
    @State private var messageConversation: Conversation?
    @State private var showReported = false
    @State private var voteFloat: Int? = nil
    @State private var upJumpTrigger: Int = 0
    @State private var downJumpTrigger: Int = 0
    
    private var canMessageAuthor: Bool {
        guard let authorId = post.authorId, let me = appState.currentUserId else { return false }
        return authorId != me
    }
    
    private var hashtags: [String] {
        AppState.extractHashtags(from: post.body)
    }
    
    private var shareText: String {
        ShareLinks.text(for: post)
    }
    
    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604800 { return "\(s / 86400)d" }
        return "\(s / 604800)sem"
    }
    
    private var authorName: String {
        let n = post.authorDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "Anónimo" : n
    }
    private var authorAvatar: String {
        let e = post.authorEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return e.isEmpty ? "A" : e
    }
    private var avatarIsEmoji: Bool {
        let e = post.authorEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !e.isEmpty
    }
    private var avatarTint: Color {
        AccentColor.from(post.authorAccentColor).color
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender row: avatar, name, school, time, menu — padding above and below for clear separation
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
                if post.isPinned {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                        Text("Aviso")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.echoGreen)
                }
                Text(relativeTime(post.createdAt))
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
            .padding(.bottom, 10)
            
            // Post body
            Text(post.body)
                .font(.system(size: 18, weight: .regular))
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color.echoText)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, post.imageURL != nil ? 12 : 14)
            
            if let urlString = post.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundStyle(Color.echoTextTertiary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 14)
            }
            
            if let poll = post.poll {
                VStack(alignment: .leading, spacing: 8) {
                    Text(poll.question)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.echoText)
                    ForEach(Array(poll.options.enumerated()), id: \.offset) { index, optionText in
                        let count = pollVoteCounts[index] ?? 0
                        let total = poll.options.indices.reduce(0) { $0 + (pollVoteCounts[$1] ?? 0) }
                        let fraction = total > 0 ? Double(count) / Double(total) : 0.0
                        let isSelected = myPollVote == index
                        Button {
                            onPollVote?(index)
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
                                    if myPollVote != nil {
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
                        .disabled(myPollVote != nil)
                    }
                }
                .padding(.bottom, 14)
            }
            
            // Hashtag chips
            if !hashtags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(hashtags.prefix(4), id: \.self) { tag in
                        Button {
                            onTapHashtag?(tag)
                        } label: {
                            Text("#\(tag)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.echoGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.echoGreen.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 10)
            }
            
            // Interaction bar: comment, share, vote — even spacing like reference
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.body)
                    Text("\(post.commentCount)")
                        .font(.body)
                }
                .foregroundStyle(Color.echoTextSecondary)
                
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                .buttonStyle(.plain)
                
                Button {
                    guard canMessageAuthor, let authorId = post.authorId else { return }
                    Task {
                        if let conv = try? await appState.getOrCreateConversation(postId: post.id, postAuthorId: authorId) {
                            messageConversation = conv
                        }
                    }
                } label: {
                    Image(systemName: "paperplane")
                        .font(.body)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                .buttonStyle(.plain)
                
                Spacer(minLength: 0)
                
                if !post.isPinned {
                    HStack(spacing: 8) {
                        Button {
                            let prev = vote
                            let next: VoteDirection = (vote == .up) ? .none : .up
                            onVote(next)
                            triggerVoteFloat(prev: prev, next: next)
                            upJumpTrigger &+= 1
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(vote == .up ? Color.echoGreen : Color.echoTextSecondary)
                                .modifier(ArrowJump(direction: .up, trigger: upJumpTrigger))
                                .frame(width: 32, height: 32)
                                .background(Color.echoVoteCircle)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        ZStack {
                            Text("\(post.score)")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.echoGreen)
                                .frame(minWidth: 28, alignment: .center)
                                .contentTransition(.numericText(value: Double(post.score)))
                                .animation(.snappy(duration: 0.12), value: post.score)
                            
                            if let delta = voteFloat {
                                FloatingDeltaLabel(delta: delta)
                            }
                        }
                        
                        Button {
                            let prev = vote
                            let next: VoteDirection = (vote == .down) ? .none : .down
                            onVote(next)
                            triggerVoteFloat(prev: prev, next: next)
                            downJumpTrigger &+= 1
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(vote == .down ? Color.echoOrange : Color.echoTextSecondary)
                                .modifier(ArrowJump(direction: .down, trigger: downJumpTrigger))
                                .frame(width: 32, height: 32)
                                .background(Color.echoVoteCircle)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 12)
            
            // Separator between posts
            Rectangle()
                .fill(Color.echoSeparator)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
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
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showReported = false }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showReported)
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

/// Makes an arrow icon "jump" in its pointing direction when `trigger` changes:
/// up arrow shoots up then springs back, down arrow shoots down then springs back.
struct ArrowJump: ViewModifier {
    enum Direction { case up, down }
    let direction: Direction
    let trigger: Int
    
    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
                view.offset(y: offset)
            } keyframes: { _ in
                SpringKeyframe(direction == .up ? -10.0 : 10.0, duration: 0.10, spring: .bouncy)
                SpringKeyframe(0.0, duration: 0.22, spring: .bouncy)
            }
    }
}

/// Small "+1" / "-1" badge that floats up and fades out. Used to give visible
/// feedback when the user up/downvotes a post or comment.
struct FloatingDeltaLabel: View {
    let delta: Int
    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Text(delta > 0 ? "+\(delta)" : "\(delta)")
            .font(.caption.weight(.bold))
            .foregroundStyle(delta > 0 ? Color.echoGreen : Color.echoOrange)
            .offset(y: offsetY)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.28)) {
                    offsetY = -24
                    opacity = 0
                }
            }
    }
}

#Preview {
    List {
        PostRowView(
            post: Post(body: "Alguien más tiene final de Cálculo mañana?", score: 42, commentCount: 8, campusId: "tec-monterrey"),
            campusName: "Tec Qro",
            vote: .none,
            onVote: { _ in }
        )
        .environmentObject(AppState())
    }
}
