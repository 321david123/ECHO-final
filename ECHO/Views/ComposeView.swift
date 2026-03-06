//
//  ComposeView.swift
//  ECHO
//

import SwiftUI
import PhotosUI
import UIKit

struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @State private var text = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isPosting = false
    @State private var postError: String?
    @State private var showPostError = false
    @FocusState private var focused: Bool
    
    @State private var addPoll = false
    @State private var pollQuestion = ""
    @State private var pollOptions = ["", ""]
    
    private var canPost: Bool {
        let bodyOk = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
        guard bodyOk else { return false }
        if addPoll {
            let q = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let opts = pollOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return !q.isEmpty && opts.count >= Poll.minOptions
        }
        return true
    }
    
    private var remaining: Int {
        Post.maxLength - text.count
    }
    
    private var validPoll: Poll? {
        guard addPoll else { return nil }
        let q = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let opts = pollOptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !q.isEmpty, opts.count >= Poll.minOptions else { return nil }
        return Poll(question: String(q.prefix(Poll.maxQuestionLength)), options: opts)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.echoBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    TextField("¿Qué está pasando en tu campus?", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .padding()
                        .focused($focused)
                        .onAppear { focused = true }
                        .foregroundStyle(Color.echoText)
                    
                    if let imageData = selectedImageData, let uiImage = UIImage(data: imageData) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            Button {
                                selectedPhoto = nil
                                selectedImageData = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                            }
                            .padding(12)
                        }
                    }
                    
                    if addPoll {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Encuesta")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.echoTextSecondary)
                            TextField("Pregunta de la encuesta", text: $pollQuestion)
                                .textFieldStyle(.roundedBorder)
                                .foregroundStyle(Color.echoText)
                            ForEach(Array(pollOptions.enumerated()), id: \.offset) { index, _ in
                                HStack(spacing: 8) {
                                    TextField("Opción \(index + 1)", text: $pollOptions[index])
                                        .textFieldStyle(.roundedBorder)
                                        .foregroundStyle(Color.echoText)
                                    if pollOptions.count > Poll.minOptions {
                                        Button {
                                            pollOptions.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(Color.echoTextTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            if pollOptions.count < Poll.maxOptions {
                                Button {
                                    pollOptions.append("")
                                } label: {
                                    Label("Añadir opción", systemImage: "plus.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.echoGreen)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(Color.echoCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    
                    HStack(alignment: .bottom, spacing: 12) {
                        Button {
                            addPoll.toggle()
                            if !addPoll { pollQuestion = ""; pollOptions = ["", ""] }
                        } label: {
                            Image(systemName: addPoll ? "chart.bar.fill" : "chart.bar")
                                .font(.title2)
                                .foregroundStyle(addPoll ? Color.echoGreen : Color.echoTextSecondary)
                        }
                        .buttonStyle(.plain)
                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Image(systemName: selectedPhoto == nil ? "photo.badge.plus" : "photo.fill")
                                .font(.title2)
                                .foregroundStyle(selectedPhoto == nil ? Color.echoTextSecondary : Color.echoGreen)
                        }
                        .onChange(of: selectedPhoto) { _, newItem in
                            Task {
                                selectedImageData = nil
                                if let item = newItem,
                                   let data = try? await item.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data),
                                   let jpeg = image.jpegData(compressionQuality: 0.8) {
                                    selectedImageData = jpeg
                                }
                            }
                        }
                        
                        Spacer()
                        Text("\(remaining)")
                            .font(.caption)
                            .foregroundStyle(remaining < 20 ? Color.echoOrange : Color.echoTextSecondary)
                        Text("Anónimo · \(appState.selectedCampus.shortName)")
                            .font(.caption)
                            .foregroundStyle(Color.echoTextTertiary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    Spacer()
                }
            }
            .navigationTitle("Nuevo ECHO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundStyle(Color.echoTextSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publicar") {
                        Task { await post() }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canPost ? Color.echoGreen : Color.echoTextSecondary)
                    .disabled(!canPost)
                }
            }
            .alert("Error al publicar", isPresented: $showPostError) {
                Button("Entendido") { showPostError = false; postError = nil }
            } message: {
                if let msg = postError { Text(msg) }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private func post() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            try await appState.addPostAsync(trimmed, imageData: selectedImageData, imageFileExtension: "jpg", poll: validPoll)
            dismiss()
        } catch {
            postError = error.localizedDescription
            showPostError = true
        }
    }
}

#Preview {
    ComposeView()
        .environmentObject(AppState())
}
