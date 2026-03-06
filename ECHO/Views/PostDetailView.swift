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
    
    private var canMessageAuthor: Bool {
        guard let authorId = post.authorId, let me = appState.currentUserId else { return false }
        return authorId != me
    }
    
    private var postOrUpdated: Post {
        appState.posts.first(where: { $0.id == post.id }) ?? post
    }
    
    private var postComments: [Comment] {
        appState.comments(for: post.id)
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(postOrUpdated.body)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.echoText)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let urlString = postOrUpdated.imageURL, let url = URL(string: urlString) {
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
                        .frame(height: 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Button {
                                appState.vote(postId: post.id, direction: appState.userVote(for: post.id) == .up ? .none : .up)
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appState.userVote(for: post.id) == .up ? Color.echoGreen : Color.echoTextSecondary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.echoVoteCircle)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            Text("\(postOrUpdated.score)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.echoGreen)
                                .frame(minWidth: 28, alignment: .center)
                            Button {
                                appState.vote(postId: post.id, direction: appState.userVote(for: post.id) == .down ? .none : .down)
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appState.userVote(for: post.id) == .down ? Color.echoOrange : Color.echoTextSecondary)
                                    .frame(width: 32, height: 32)
                                    .background(Color.echoVoteCircle)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        Text(postOrUpdated.createdAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(Color.echoTextTertiary)
                        
                        if let poll = postOrUpdated.poll {
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
                            .padding(.top, 8)
                        }
                        
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
                                Label("Enviar mensaje al autor", systemImage: "paperplane")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.echoGreen)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(Color.echoCard)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            
            if let err = messageError {
                Section {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.echoOrange)
                }
                .listRowBackground(Color.echoCard)
            }
            
            Section("Comentarios") {
                ForEach(postComments) { comment in
                    CommentRowView(comment: comment)
                        .listRowBackground(Color.echoCard)
                }
                
                HStack(spacing: 8) {
                    TextField("Responder anónimamente...", text: $commentText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($commentFocused)
                    Button {
                        submitComment()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.echoTextSecondary : Color.echoGreen)
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.echoCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
    }
    
    private func submitComment() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addComment(trimmed, postId: post.id)
        commentText = ""
    }
}

private struct CommentRowView: View {
    let comment: Comment
    
    /// Relative time without seconds: "ahora", "5m", "2h", "3d".
    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604800 { return "\(s / 86400)d" }
        return "\(s / 604800)sem"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.body)
                .font(.body)
                .foregroundStyle(Color.echoText)
            Text(relativeTime(comment.createdAt))
                .font(.caption)
                .foregroundStyle(Color.echoTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        PostDetailView(post: Post(body: "Alguien más tiene final mañana?", score: 42, commentCount: 2, campusId: "tec-monterrey"))
            .environmentObject(AppState())
    }
}
