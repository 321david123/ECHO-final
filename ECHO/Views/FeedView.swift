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
    @State private var showingInvite = false

    var body: some View {
        NavigationStack(path: $appState.feedPath) {
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
                .navigationDestination(for: HashtagRoute.self) { route in
                    HashtagFeedView(tag: route.tag)
                        .onAppear { Task { await appState.loadHashtagFeed(route.tag) } }
                }
        }
        .preferredColorScheme(.dark)
    }
    
    private var feedScrollView: some View {
        ZStack(alignment: .top) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    feedHeader
                    if appState.useSupabase && !appState.isReviewerSession {
                        inviteEventBanner
                    }
                    feedPostRows
                }
                .background(scrollOffsetBackground)
            }
            .sheet(isPresented: $showingInvite) {
                InviteFriendsView()
                    .environmentObject(appState)
            }
            .refreshable {
                Haptics.voteTick()
                await appState.loadPosts()
                try? await Task.sleep(nanoseconds: 200_000_000)
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
            .scrollIndicators(.hidden)
            
            // First-post tooltip (auto-dismiss, also dismisses on tap)
            if !appState.hasSeenFirstPostTooltip && !appState.visiblePosts.isEmpty {
                FirstPostTooltip {
                    appState.markFirstPostTooltipSeen()
                }
                .padding(.top, 80)
                .transition(.opacity)
            }
        }
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
    
    /// Compact event banner: "Invita y Gana" (regreso a clases).
    private var inviteEventBanner: some View {
        Button {
            showingInvite = true
        } label: {
            HStack(spacing: 10) {
                Text("☕️")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("Invita y Gana")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.echoText)
                        Text("LIMITADO")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AccentColor.gold.color)
                            .clipShape(Capsule())
                    }
                    Text("1 amig@ = badge OG 🐿️ · \(AppState.referralsPerDrink) = bebida gratis ☕️")
                        .font(.caption)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                Spacer(minLength: 0)
                if appState.completedReferralCount > 0 {
                    Text("\(appState.completedReferralCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.echoGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.echoGreen.opacity(0.15))
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.echoGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.echoCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.echoGreen.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
                onPollVote: post.poll != nil ? { appState.votePoll(postId: post.id, optionIndex: $0) } : nil,
                onTapHashtag: { tag in
                    Task {
                        await appState.loadHashtagFeed(tag)
                        await MainActor.run {
                            appState.feedPath.append(HashtagRoute(tag: tag))
                        }
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .listRowBackground(Color.echoBackground)
    }
}

/// Small overlay that hints "tap a post to see comments" on the user's first feed view.
private struct FirstPostTooltip: View {
    let onDismiss: () -> Void
    @State private var isVisible: Bool = true
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(Color.echoGreen)
            Text("Toca un post para ver comentarios, crear un hilo, mandar mensaje privado o compartir el post!")
                .font(.caption)
                .foregroundStyle(Color.echoText)
            Spacer(minLength: 0)
            Button {
                isVisible = false
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Color.echoTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.echoCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.echoGreen.opacity(0.15), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 24)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                withAnimation(.easeOut(duration: 0.4)) { isVisible = false }
                onDismiss()
            }
        }
        .onTapGesture {
            withAnimation { isVisible = false }
            onDismiss()
        }
    }
}

#Preview {
    FeedView()
        .environmentObject(AppState())
}
