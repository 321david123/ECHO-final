//
//  ConversationThreadView.swift
//  ECHO
//

import SwiftUI

struct ConversationThreadView: View {
    @EnvironmentObject var appState: AppState
    let conversation: Conversation
    @State private var messageText = ""
    @FocusState private var messageFocused: Bool
    
    private var messages: [PrivateMessage] {
        appState.messages(for: conversation.id)
    }
    
    private var isMe: (UUID) -> Bool {
        { senderId in appState.currentUserId == senderId }
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Sobre el post")
                    .font(.caption)
                    .foregroundStyle(Color.echoTextTertiary)
                Text(conversation.postBodySnippet)
                    .font(.subheadline)
                    .foregroundStyle(Color.echoTextSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.echoCard)
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            if isMe(msg.senderId) {
                                HStack(alignment: .bottom) {
                                    Spacer(minLength: 60)
                                    Text(msg.body)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.echoGreen.opacity(0.25))
                                        .foregroundStyle(Color.echoText)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .id(msg.id)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 10) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.echoGreen.opacity(0.35))
                                                .frame(width: 36, height: 36)
                                            Text("A")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.echoGreen)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Anónimo")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(Color.echoText)
                                            HStack(spacing: 6) {
                                                Text((appState.verifiedCampus ?? appState.selectedCampus).shortName)
                                                    .font(.caption)
                                                    .foregroundStyle(Color.echoTextSecondary)
                                                Text(relativeTime(msg.createdAt))
                                                    .font(.caption)
                                                    .foregroundStyle(Color.echoTextTertiary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    Text(msg.body)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.echoText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.echoCard)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(msg.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            
            HStack(spacing: 8) {
                TextField("Mensaje...", text: $messageText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($messageFocused)
                    .padding(10)
                    .background(Color.echoCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    appState.sendMessage(conversationId: conversation.id, body: messageText)
                    messageText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.echoTextTertiary : Color.echoGreen)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color.echoBackground)
        }
        .background(Color.echoBackground)
        .navigationTitle("Conversación")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if appState.useSupabase { Task { await appState.loadMessages(conversationId: conversation.id) } }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack {
        ConversationThreadView(conversation: Conversation(
            id: UUID(),
            postId: UUID(),
            postBodySnippet: "Alguien más tiene final de Cálculo mañana?",
            postAuthorId: UUID(),
            initiatorId: UUID(),
            createdAt: Date(),
            lastMessageAt: nil,
            lastMessageBody: nil
        ))
        .environmentObject(AppState())
    }
}
