//
//  MessagesView.swift
//  ECHO
//

import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var appState: AppState
    
    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "ahora" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        if s < 604800 { return "\(s / 86400)d" }
        return "\(s / 604800)sem"
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if appState.useSupabase && !appState.conversations.isEmpty {
                    List {
                        ForEach(appState.conversations) { conv in
                            NavigationLink(value: conv) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conv.postBodySnippet)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.echoText)
                                        .lineLimit(2)
                                    Text(relativeTime(conv.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(Color.echoTextTertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.echoCard)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("Envía un mensaje directo desde un post en Inicio para iniciar una conversación.")
                            .font(.subheadline)
                            .foregroundStyle(Color.echoTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.echoBackground)
            .navigationTitle("Mensajes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Conversation.self) { conv in
                ConversationThreadView(conversation: conv)
            }
            .onAppear {
                if appState.useSupabase { Task { await appState.loadConversations() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MessagesView()
        .environmentObject(AppState())
}
