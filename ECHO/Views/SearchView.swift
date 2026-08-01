//
//  SearchView.swift
//  ECHO
//

import SwiftUI

/// Full-text search over posts in the user's verified campus.
/// Presented as a sheet from `ExplorarView` (small entry point, not full-screen by default).
struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                
                Divider().background(Color.echoSeparator.opacity(0.4))
                
                if appState.isSearching {
                    Spacer()
                    ProgressView().tint(Color.echoGreen)
                    Spacer()
                } else if appState.searchResults.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .background(Color.echoBackground)
            .navigationTitle("Buscar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        appState.clearSearch()
                        dismiss()
                    }
                    .foregroundStyle(Color.echoGreen)
                }
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(post: post)
            }
            .onAppear { inputFocused = true }
            .onDisappear {
                searchTask?.cancel()
                appState.clearSearch()
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.echoTextSecondary)
            TextField("Buscar posts...", text: $query)
                .focused($inputFocused)
                .foregroundStyle(Color.echoText)
                .submitLabel(.search)
                .onSubmit { triggerSearch(immediate: true) }
                .onChange(of: query) { _, _ in triggerSearch(immediate: false) }
            if !query.isEmpty {
                Button { query = ""; appState.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.echoTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.echoCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Color.echoTextTertiary)
            Text(query.isEmpty ? "Escribe para buscar." : "Sin resultados.")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.searchResults) { post in
                    NavigationLink(value: post) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(Color.echoText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                Text(Campus.mexicanUniversities.first(where: { $0.id == post.campusId })?.shortName ?? "")
                                    .font(.caption)
                                    .foregroundStyle(Color.echoTextSecondary)
                                Text("·")
                                    .foregroundStyle(Color.echoTextTertiary)
                                Text("\(post.score) ▲ · \(post.commentCount) 💬")
                                    .font(.caption)
                                    .foregroundStyle(Color.echoTextTertiary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Rectangle()
                        .fill(Color.echoSeparator.opacity(0.4))
                        .frame(height: 1)
                }
            }
        }
    }
    
    private func triggerSearch(immediate: Bool) {
        searchTask?.cancel()
        let q = query
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000) // debounce 350ms
                if Task.isCancelled { return }
            }
            await appState.runSearch(q)
        }
    }
}

#Preview {
    SearchView().environmentObject(AppState())
}
