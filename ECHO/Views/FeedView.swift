//
//  FeedView.swift
//  ECHO
//

import SwiftUI

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationStack {
            feedScrollView
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if appState.useSupabase { Task { await appState.loadPosts() } }
                }
                .onChange(of: appState.feedSort) { _, _ in
                    if appState.useSupabase { Task { await appState.loadPosts() } }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationDestination(for: Post.self) { post in
                    PostDetailView(post: post)
                }
        }
        .preferredColorScheme(.dark)
    }
    
    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                feedHeader
                feedPostRows
            }
            .background(scrollOffsetBackground)
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { topGlobalY in
            withAnimation(.easeInOut(duration: 0.25)) {
                if topGlobalY < 80 {
                    appState.isTabBarCompact = true
                } else if topGlobalY > 120 {
                    appState.isTabBarCompact = false
                }
            }
        }
        .refreshable {
            if appState.useSupabase {
                await appState.loadPosts()
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.echoBackground)
    }
    
    private var feedHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            Text("ECHO")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.echoText)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(AppState.FeedSort.allCases.enumerated()), id: \.offset) { index, sort in
                    Button {
                        appState.feedSort = sort
                    } label: {
                        Text(sort.rawValue)
                            .font(.body)
                            .fontWeight(appState.feedSort == sort ? .semibold : .regular)
                            .foregroundStyle(appState.feedSort == sort ? Color.echoText : Color.echoTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    if index < AppState.FeedSort.allCases.count - 1 {
                        Text(" · ")
                            .font(.body)
                            .foregroundStyle(Color.echoTextTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.echoBackground)
    }
    
    @ViewBuilder
    private var feedPostRows: some View {
        ForEach(appState.visiblePosts) { post in
            FeedPostRowLink(post: post)
        }
    }
    
    private var scrollOffsetBackground: some View {
        GeometryReader { g in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: g.frame(in: .global).minY
            )
        }
    }
}

private struct FeedPostRowLink: View {
    let post: Post
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        NavigationLink(value: post) {
            PostRowView(
                post: post,
                campusName: Campus.mexicanUniversities.first(where: { $0.id == post.campusId })?.shortName ?? "Campus",
                vote: appState.userVote(for: post.id),
                onVote: { direction in appState.vote(postId: post.id, direction: direction) },
                pollVoteCounts: appState.pollVoteCounts[post.id] ?? [:],
                myPollVote: appState.myPollVote(for: post.id),
                onPollVote: post.poll != nil ? { appState.votePoll(postId: post.id, optionIndex: $0) } : nil
            )
        }
        .padding(.horizontal, 20)
        .listRowBackground(Color.echoBackground)
    }
}

#Preview {
    FeedView()
        .environmentObject(AppState())
}
