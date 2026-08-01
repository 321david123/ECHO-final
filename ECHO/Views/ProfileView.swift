//
//  ProfileView.swift
//  ECHO
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingCampus = false
    @State private var showingPrivacy = false
    @State private var showingSignOutConfirmation = false
    @State private var showingReport = false
    @State private var showingTerms = false
    @State private var showingAbout = false
    @State private var showingEditDisplay = false
    @State private var showingInvite = false
    
    private var resolvedDisplayName: String {
        let trimmed = appState.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Anónimo" : trimmed
    }
    
    private var resolvedEmojiOrLetter: String {
        if let e = appState.userEmoji?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return e
        }
        return String((appState.verifiedCampus ?? appState.selectedCampus).shortName.prefix(1))
    }
    
    private var isEmojiAvatar: Bool {
        let e = appState.userEmoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !e.isEmpty
    }
    
    private var avatarTint: Color {
        AccentColor.from(appState.userAccentColor).color
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(avatarTint.opacity(0.3))
                                    .frame(width: 64, height: 64)
                                Text(resolvedEmojiOrLetter)
                                    .font(.system(size: 32))
                                    .fontWeight(.bold)
                                    .foregroundStyle(isEmojiAvatar ? Color.echoText : avatarTint)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(resolvedDisplayName)
                                        .font(.headline)
                                        .foregroundStyle(Color.echoText)
                                    if appState.hasOGBadge {
                                        Text("OG 🐿️")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(AccentColor.gold.color)
                                            .clipShape(Capsule())
                                    }
                                }
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.echoGreen)
                                    Text("\(appState.userKarma) karma")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.echoTextSecondary)
                                }
                                if let campus = appState.verifiedCampus ?? (appState.useSupabase ? nil : Optional(appState.selectedCampus)) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.echoGreen)
                                        Text("Verificado · \(campus.shortName)")
                                            .font(.caption)
                                            .foregroundStyle(Color.echoTextSecondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        
                        Button {
                            showingEditDisplay = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                Text("Editar perfil")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.echoGreen.opacity(0.7))
                            }
                            .foregroundStyle(Color.echoGreen)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.echoGreen.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.echoCard)
                .listRowSeparator(.hidden)
                
                Section("Cuenta") {
                    Button {
                        showingInvite = true
                    } label: {
                        HStack {
                            Label("Invita y Gana ☕️", systemImage: "gift")
                                .foregroundStyle(Color.echoText)
                            Spacer()
                            if appState.completedReferralCount > 0 {
                                Text("\(appState.completedReferralCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.echoGreen)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.echoCard)

                    Button {
                        showingCampus = true
                    } label: {
                        HStack {
                            Label("Mi campus", systemImage: "building.2")
                                .foregroundStyle(Color.echoText)
                            Spacer()
                            if let c = appState.verifiedCampus ?? (appState.useSupabase ? nil : Optional(appState.selectedCampus)) {
                                Text(c.shortName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.echoTextSecondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.echoCard)
                    
                    Button {
                        showingPrivacy = true
                    } label: {
                        HStack {
                            Label("Privacidad", systemImage: "lock")
                                .foregroundStyle(Color.echoText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.echoCard)
                }
                
                Section("Soporte") {
                    Button {
                        showingReport = true
                    } label: {
                        HStack {
                            Label("Reportar problema", systemImage: "flag")
                                .foregroundStyle(Color.echoText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.echoCard)
                    
                    Button {
                        showingTerms = true
                    } label: {
                        HStack {
                            Label("Términos y privacidad", systemImage: "doc.text")
                                .foregroundStyle(Color.echoText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.echoCard)
                    
                    Button {
                        showingAbout = true
                    } label: {
                        HStack {
                            Label("Acerca de ECHO", systemImage: "info.circle")
                                .foregroundStyle(Color.echoText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.echoTextTertiary)
                        }
                    }
                    .listRowBackground(Color.echoCard)
                }
                
                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Cerrar sesión")
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.echoCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.echoBackground)
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingCampus) {
                MiCampusSheet(campus: appState.verifiedCampus ?? appState.selectedCampus)
            }
            .sheet(isPresented: $showingInvite) {
                InviteFriendsView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingPrivacy) {
                PrivacySheet()
            }
            .sheet(isPresented: $showingReport) {
                ReportSheet()
            }
            .sheet(isPresented: $showingTerms) {
                TermsSheet()
            }
            .sheet(isPresented: $showingAbout) {
                AboutSheet()
            }
            .sheet(isPresented: $showingEditDisplay) {
                EditDisplaySheet(
                    initialName: appState.displayName ?? "",
                    initialEmoji: appState.userEmoji ?? "",
                    initialColor: AccentColor.from(appState.userAccentColor),
                    userKarma: appState.userKarma,
                    completedReferrals: appState.completedReferralCount
                ) { name, emoji, color in
                    try? await appState.updateProfileDisplay(displayName: name, emoji: emoji, accentColor: color)
                }
            }
            .confirmationDialog("Cerrar sesión", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
                Button("Cancelar", role: .cancel) {}
                Button("Cerrar sesión", role: .destructive) {
                    Task { try? await appState.signOut() }
                }
            } message: {
                Text("¿Seguro que quieres cerrar sesión? Tendrás que volver a verificar tu correo institucional para entrar de nuevo.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Profile detail sheets

private struct MiCampusSheet: View {
    let campus: Campus
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "building.2.fill")
                        .font(.title)
                        .foregroundStyle(Color.echoGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(campus.name)
                            .font(.headline)
                            .foregroundStyle(Color.echoText)
                        Text(campus.city)
                            .font(.subheadline)
                            .foregroundStyle(Color.echoTextSecondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.echoCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.echoGreen)
                    Text("Tu cuenta está verificada en este campus. Solo ves y publicas en este feed.")
                        .font(.subheadline)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.echoBackground)
            .navigationTitle("Mi campus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct NotificationsSheet: View {
    @Binding var notificationsEnabled: Bool
    @Binding var commentRepliesEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Notificaciones", isOn: $notificationsEnabled)
                        .tint(Color.echoGreen)
                    Toggle("Respuestas a comentarios", isOn: $commentRepliesEnabled)
                        .tint(Color.echoGreen)
                }
                .listRowBackground(Color.echoCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.echoBackground)
            .navigationTitle("Notificaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tu actividad en ECHO es anónima. No compartimos tu identidad con otros usuarios. Los datos de verificación (correo institucional) se usan solo para confirmar que perteneces a tu campus.")
                    .font(.body)
                    .foregroundStyle(Color.echoTextSecondary)
                Spacer()
            }
            .padding()
            .background(Color.echoBackground)
            .navigationTitle("Privacidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Para reportar un problema o contenido inapropiado, escribe a contacto@sonriemexico.org")
                    .font(.body)
                    .foregroundStyle(Color.echoTextSecondary)
                Spacer()
            }
            .padding()
            .background(Color.echoBackground)
            .navigationTitle("Reportar problema")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct TermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Términos de uso y política de privacidad de ECHO. Al usar la app aceptas nuestras condiciones. Contenido anónimo sujeto a normas de la comunidad.")
                        .font(.body)
                        .foregroundStyle(Color.echoTextSecondary)
                }
                .padding()
            }
            .background(Color.echoBackground)
            .navigationTitle("Términos y privacidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("ECHO")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.echoText)
                Text("La voz de tu campus. Anónimo.")
                    .font(.subheadline)
                    .foregroundStyle(Color.echoTextSecondary)
                Text("Versión 1.0.4")
                    .font(.caption)
                    .foregroundStyle(Color.echoTextTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.echoBackground)
            .navigationTitle("Acerca de")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Edit display sheet

/// Emoji options grouped by karma required. Users unlock tiers as they earn upvotes.
private struct EmojiTier {
    let karmaRequired: Int
    let title: String
    let emojis: [String]
}

private let emojiTiers: [EmojiTier] = [
    EmojiTier(
        karmaRequired: 0,
        title: "Disponibles",
        emojis: ["🐸", "🐙", "🚀", "👾", "🎮", "🎧", "🎨", "📚",
                 "⚽️", "🏀", "🌮", "🍕", "☕️", "🍩", "😎", "🤓",
                 "🌙", "🌊", "🌿"]
    ),
    EmojiTier(
        karmaRequired: 10,
        title: "10 karma",
        emojis: ["🦊", "🐼", "🐨", "🦁", "✨"]
    ),
    EmojiTier(
        karmaRequired: 20,
        title: "20 karma",
        emojis: ["🥷", "🧠", "💡", "🦄"]
    ),
    EmojiTier(
        karmaRequired: 50,
        title: "50 karma",
        emojis: ["🔥", "⚡️", "💎", "🐲"]
    ),
    EmojiTier(
        karmaRequired: 1000,
        title: "1000 karma · GOAT",
        emojis: ["🐐"]
    ),
]

private struct EditDisplaySheet: View {
    let initialName: String
    let initialEmoji: String
    let initialColor: AccentColor
    let userKarma: Int
    /// Completed referrals — gates the OG 🐿️ emoji (1) and gold color (5).
    let completedReferrals: Int
    let onSave: (String?, String?, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var color: AccentColor
    @State private var isSaving = false
    @State private var lockedMessage: String?
    @FocusState private var nameFocused: Bool

    private var ogUnlocked: Bool { completedReferrals >= AppState.referralOGBadgeAt }
    private var goldUnlocked: Bool { completedReferrals >= AppState.referralGoldProfileAt }

    init(initialName: String, initialEmoji: String, initialColor: AccentColor, userKarma: Int, completedReferrals: Int, onSave: @escaping (String?, String?, String?) async -> Void) {
        self.initialName = initialName
        self.initialEmoji = initialEmoji
        self.initialColor = initialColor
        self.userKarma = userKarma
        self.completedReferrals = completedReferrals
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _emoji = State(initialValue: initialEmoji)
        _color = State(initialValue: initialColor)
    }
    
    private var previewText: String {
        let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? "A" : e
    }
    
    private var previewIsEmoji: Bool {
        !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func tierUnlocked(_ tier: EmojiTier) -> Bool {
        userKarma >= tier.karmaRequired
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Avatar preview
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(color.color.opacity(0.3))
                                .frame(width: 96, height: 96)
                            Text(previewText)
                                .font(.system(size: 46))
                                .fontWeight(.bold)
                                .foregroundStyle(previewIsEmoji ? Color.echoText : color.color)
                        }
                        Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Anónimo" : name)
                            .font(.headline)
                            .foregroundStyle(Color.echoText)
                        Text("\(userKarma) karma")
                            .font(.caption)
                            .foregroundStyle(Color.echoGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    
                    // Name field (keyboard is fine here — users type their name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOMBRE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.echoTextTertiary)
                        TextField("Anónimo", text: $name)
                            .focused($nameFocused)
                            .padding(12)
                            .background(Color.echoCard)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Color.echoText)
                            .onChange(of: name) { _, newValue in
                                if newValue.count > 24 { name = String(newValue.prefix(24)) }
                            }
                        Text("Máx. 24 caracteres. Déjalo vacío para ser Anónimo.")
                            .font(.caption)
                            .foregroundStyle(Color.echoTextTertiary)
                    }
                    
                    // Emoji picker — selection only, no keyboard input
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("EMOJI")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.echoTextTertiary)
                            Spacer()
                            if !emoji.isEmpty {
                                Button {
                                    emoji = ""
                                } label: {
                                    Text("Quitar")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.echoOrange)
                                }
                            }
                        }
                        
                        ogTierSection

                        ForEach(emojiTiers, id: \.karmaRequired) { tier in
                            emojiTierSection(tier)
                        }
                        
                        if let msg = lockedMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(Color.echoOrange)
                                .transition(.opacity)
                        }
                    }
                    
                    // Color picker (gold is exclusive: 5 referidos completados)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COLOR DE FONDO")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.echoTextTertiary)
                        HStack(spacing: 12) {
                            ForEach(AccentColor.allCases, id: \.self) { c in
                                let locked = c.isExclusive && !goldUnlocked
                                Button {
                                    if locked {
                                        withAnimation { lockedMessage = "El color dorado se desbloquea con \(AppState.referralGoldProfileAt) referidos completados en Invita y Gana ✨ Solo durante el evento de lanzamiento." }
                                    } else {
                                        color = c
                                        lockedMessage = nil
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(c.color.opacity(locked ? 0.15 : 0.4))
                                            .frame(width: 36, height: 36)
                                        if locked {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.echoTextTertiary)
                                        } else if color == c {
                                            Circle()
                                                .stroke(c.color, lineWidth: 3)
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(c.color)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if goldUnlocked {
                            Text("✨ Perfil dorado desbloqueado — es opcional: elígelo cuando quieras usarlo en tus posts, o quédate con tu color de siempre.")
                                .font(.caption)
                                .foregroundStyle(AccentColor.gold.color)
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
            .background(Color.echoBackground)
            .navigationTitle("Personaliza tu perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Color.echoTextSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isSaving = true
                            await onSave(
                                name.isEmpty ? nil : name,
                                emoji.isEmpty ? nil : emoji,
                                color.rawValue
                            )
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView().tint(Color.echoGreen)
                        } else {
                            Text("Guardar").fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(Color.echoGreen)
                    .disabled(isSaving)
                }
            }
            .onAppear { nameFocused = true }
        }
        .preferredColorScheme(.dark)
    }
    
    /// Exclusive OG tier: the Echo squirrel 🐿️, unlocked by 1 completed referral
    /// (Invita y Gana) — not by karma.
    private var ogTierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: ogUnlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(ogUnlocked ? AccentColor.gold.color : Color.echoTextTertiary)
                Text("OG · INVITA A 1 AMIG@")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ogUnlocked ? AccentColor.gold.color : Color.echoTextTertiary)
            }
            HStack {
                Button {
                    if ogUnlocked {
                        emoji = "🐿️"
                        lockedMessage = nil
                    } else {
                        withAnimation { lockedMessage = "El squirrel OG se desbloquea cuando tu primer invitad@ publica su echo (Invita y Gana). Solo durante el evento de lanzamiento 🐿️" }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(emoji == "🐿️" ? AccentColor.gold.color.opacity(0.3) : Color.echoCard)
                            .frame(width: 38, height: 38)
                        Text("🐿️")
                            .font(.system(size: 24))
                            .opacity(ogUnlocked ? 1.0 : 0.3)
                            .grayscale(ogUnlocked ? 0 : 1)
                        if !ogUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.echoTextTertiary)
                                .padding(3)
                                .background(Circle().fill(Color.echoBackground))
                                .offset(x: 12, y: -12)
                        }
                    }
                }
                .buttonStyle(.plain)
                Text("El squirrel de Echo. Solo primeros usuarios — legacy para siempre. Úsalo si quieres.")
                    .font(.caption)
                    .foregroundStyle(Color.echoTextTertiary)
            }
        }
    }

    @ViewBuilder
    private func emojiTierSection(_ tier: EmojiTier) -> some View {
        let unlocked = tierUnlocked(tier)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(unlocked ? Color.echoGreen : Color.echoTextTertiary)
                Text(tier.title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(unlocked ? Color.echoText : Color.echoTextTertiary)
                if !unlocked {
                    Text("· te faltan \(tier.karmaRequired - userKarma)")
                        .font(.caption)
                        .foregroundStyle(Color.echoTextTertiary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(tier.emojis, id: \.self) { e in
                    Button {
                        if unlocked {
                            emoji = e
                            lockedMessage = nil
                        } else {
                            withAnimation { lockedMessage = "Este emoji se desbloquea con \(tier.karmaRequired) karma. Publica y recibe upvotes para subir." }
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(emoji == e ? color.color.opacity(0.3) : Color.echoCard)
                                .frame(width: 38, height: 38)
                            Text(e)
                                .font(.system(size: 24))
                                .opacity(unlocked ? 1.0 : 0.3)
                                .grayscale(unlocked ? 0 : 1)
                            if !unlocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.echoTextTertiary)
                                    .padding(3)
                                    .background(Circle().fill(Color.echoBackground))
                                    .offset(x: 12, y: -12)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    let state = AppState()
    state.hasCompletedOnboarding = true
    state.verifiedCampus = Campus.mexicanUniversities[0]
    return ProfileView()
        .environmentObject(state)
}
