//
//  PostRowView.swift
//  ECHO
//

import SwiftUI

struct PostRowView: View {
    let post: Post
    let campusName: String
    let vote: VoteDirection
    let onVote: (VoteDirection) -> Void
    var pollVoteCounts: [Int: Int] = [:]
    var myPollVote: Int? = nil
    var onPollVote: ((Int) -> Void)? = nil
    
    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604800 { return "\(s / 86400)d" }
        return "\(s / 604800)sem"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender row: avatar, name, school, time, menu — padding above and below for clear separation
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.echoGreen.opacity(0.35))
                        .frame(width: 40, height: 40)
                    Text("A")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.echoGreen)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anónimo")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.echoText)
                    Text(campusName)
                        .font(.subheadline)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                Spacer(minLength: 0)
                Text(relativeTime(post.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(Color.echoTextTertiary)
                Button { } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.echoTextSecondary)
                }
                .buttonStyle(.plain)
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
            
            // Interaction bar: comment, share, vote — even spacing like reference
            HStack(spacing: 20) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.body)
                    Text("\(post.commentCount)")
                        .font(.body)
                }
                .foregroundStyle(Color.echoTextSecondary)
                
                Image(systemName: "paperplane")
                    .font(.body)
                    .foregroundStyle(Color.echoTextSecondary)
                
                Spacer(minLength: 0)
                
                HStack(spacing: 8) {
                    Button {
                        onVote(vote == .up ? .none : .up)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(vote == .up ? Color.echoGreen : Color.echoTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.echoVoteCircle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(post.score)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.echoGreen)
                        .frame(minWidth: 28, alignment: .center)
                    
                    Button {
                        onVote(vote == .down ? .none : .down)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(vote == .down ? Color.echoOrange : Color.echoTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.echoVoteCircle)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            
            // Separator between posts
            Rectangle()
                .fill(Color.echoSeparator)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
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
    }
}
