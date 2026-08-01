//
//  HashtagFeedView.swift
//  ECHO
//

import SwiftUI

/// Feed of all posts in the user's campus that contain a given hashtag.
struct HashtagFeedView: View {
    @EnvironmentObject var appState: AppState
    let tag: String
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if appState.hashtagFeed.isEmpty {
                    VStack(spacing: 8) {
                        Spacer(minLength: 80)
                        Image(systemName: "number")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.echoTextTertiary)
                        Text("Aún no hay posts con #\(tag)")
                            .font(.subheadline)
                            .foregroundStyle(Color.echoTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
                
                ForEach(appState.hashtagFeed) { post in
                    NavigationLink(value: post) {
                        PostRowView(
                            post: post,
                            campusName: Campus.mexicanUniversities.first(where: { $0.id == post.campusId })?.shortName ?? "Campus",
                            vote: appState.userVote(for: post.id),
                            onVote: { direction in appState.vote(postId: post.id, direction: direction) },
                            pollVoteCounts: appState.pollVoteCounts[post.id] ?? [:],
                            myPollVote: appState.myPollVote(for: post.id),
                            onPollVote: post.poll != nil ? { appState.votePoll(postId: post.id, optionIndex: $0) } : nil,
                            onTapHashtag: { newTag in
                                Task { await appState.loadHashtagFeed(newTag) }
                            }
                        )
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .background(Color.echoBackground)
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        HashtagFeedView(tag: "examenes")
            .environmentObject(AppState())
    }
}
