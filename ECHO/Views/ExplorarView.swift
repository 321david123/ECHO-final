//
//  ExplorarView.swift
//  ECHO
//

import SwiftUI

struct ExplorarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSearch = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Full-width search pill. Tapping opens SearchView as a sheet.
                    Button {
                        showingSearch = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                            Text("Buscar posts, hashtags...")
                                .font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.echoTextSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.echoCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    
                    // Trending hashtags
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tendencias")
                            .font(.headline)
                            .foregroundStyle(Color.echoText)
                        
                        if appState.trendingTags.isEmpty {
                            Text("Aún no hay hashtags. Usa #palabra al postear.")
                                .font(.subheadline)
                                .foregroundStyle(Color.echoTextSecondary)
                                .padding(.vertical, 8)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(appState.trendingTags, id: \.tag) { item in
                                    NavigationLink(value: item.tag) {
                                        HStack(spacing: 6) {
                                            Text("#\(item.tag)")
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(item.count)")
                                                .font(.caption)
                                                .foregroundStyle(Color.echoTextSecondary)
                                        }
                                        .foregroundStyle(Color.echoGreen)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.echoGreen.opacity(0.12))
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.echoBackground)
            .navigationTitle("Explorar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: String.self) { tag in
                HashtagFeedView(tag: tag)
                    .onAppear { Task { await appState.loadHashtagFeed(tag) } }
            }
            .onAppear {
                Task { await appState.loadTrendingTags() }
            }
            .refreshable {
                await appState.loadTrendingTags()
            }
            .sheet(isPresented: $showingSearch) {
                SearchView().environmentObject(appState)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Simple wrap-flow layout for hashtag chips (iOS 16+).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    ExplorarView().environmentObject(AppState())
}
