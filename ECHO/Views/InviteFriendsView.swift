//
//  InviteFriendsView.swift
//  ECHO
//
//  "Invita y Gana" — evento de regreso a clases.
//  Comparte tu código; cuando tu amig@ se registra con su correo institucional
//  y publica su primer echo, sumas 1 referido. Cada 3 = una bebida gratis
//  (Starbucks / Tim Hortons). Sin límite de premios.
//

import SwiftUI
import UIKit

struct InviteFriendsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copiedCode = false
    @State private var showClaimSheet = false

    private var perDrink: Int { AppState.referralsPerDrink }
    private var completed: Int { appState.completedReferralCount }
    /// Progress toward the next drink; shows a full bar (10/10) right when one is earned.
    private var drinkDisplay: Int {
        let p = appState.referralDrinkProgress
        return (completed > 0 && p == 0) ? perDrink : p
    }
    private var campusShort: String {
        (appState.verifiedCampus ?? appState.selectedCampus).shortName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    codeCard
                    progressCard
                    if !appState.myReferralRewards.isEmpty {
                        rewardsCard
                    }
                    howItWorksCard
                    if appState.myReferralClaim == nil {
                        claimEntryButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color.echoBackground)
            .navigationTitle("Invita y Gana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.echoGreen)
                }
            }
            .onAppear {
                Task { await appState.loadReferralData() }
            }
            .refreshable {
                await appState.loadReferralData()
            }
            .sheet(isPresented: $showClaimSheet) {
                ReferralClaimSheet()
                    .environmentObject(appState)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("☕️")
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Evento de lanzamiento otoño")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.echoGreen)
                        Text("LIMITADO")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AccentColor.gold.color)
                            .clipShape(Capsule())
                    }
                    Text("Invita amigos, gana premios")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.echoText)
                }
            }
            Text("Cada amig@ cuenta cuando se registra con su correo y publica su primer echo. Los premios se acumulan:")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .lineSpacing(2)
            Text("⏳ Solo para los primeros: cuando termine el evento, el badge OG y el perfil dorado se vuelven legacy — quien los ganó los conserva para siempre y nadie más los podrá conseguir.")
                .font(.caption)
                .foregroundStyle(AccentColor.gold.color)
                .lineSpacing(2)
        }
        .padding(.top, 12)
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            Text("TU CÓDIGO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.echoTextTertiary)

            if let code = appState.referralCode {
                Button {
                    UIPasteboard.general.string = code
                    Haptics.voteTick()
                    withAnimation { copiedCode = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copiedCode = false }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(code)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .kerning(4)
                            .foregroundStyle(Color.echoGreen)
                        Image(systemName: copiedCode ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.body)
                            .foregroundStyle(copiedCode ? Color.echoGreen : Color.echoTextSecondary)
                    }
                }
                .buttonStyle(.plain)

                if copiedCode {
                    Text("Copiado")
                        .font(.caption)
                        .foregroundStyle(Color.echoGreen)
                }

                ShareLink(item: ShareLinks.inviteText(code: code, campusShortName: campusShort)) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Invitar amigos")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.echoGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                ProgressView()
                    .tint(Color.echoGreen)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color.echoCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tu progreso")
                    .font(.headline)
                    .foregroundStyle(Color.echoText)
                Spacer()
                Text("\(completed) referid\(completed == 1 ? "o" : "os")")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.echoGreen)
            }

            // Escalera de premios
            milestoneRow(
                emoji: "🐿️",
                target: AppState.referralOGBadgeAt,
                title: "Badge OG",
                subtitle: "El squirrel de Echo para tu avatar. Solo primeros usuarios — tuyo para siempre.",
                achieved: appState.hasOGBadge
            )
            milestoneRow(
                emoji: "✨",
                target: AppState.referralGoldProfileAt,
                title: "Perfil dorado",
                subtitle: "Color dorado exclusivo. Opcional: tú eliges si usarlo en tus posts.",
                achieved: appState.hasGoldProfile
            )
            milestoneRow(
                emoji: "☕️",
                target: perDrink,
                title: "Bebida gratis",
                subtitle: "Starbucks o Tim Hortons. Se repite cada \(perDrink): \(perDrink * 2) = 2 bebidas…",
                achieved: appState.referralDrinksEarned > 0
            )

            // Barra hacia la (próxima) bebida
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.echoVoteCircle)
                            .frame(height: 8)
                        Capsule()
                            .fill(Color.echoGreen)
                            .frame(width: max(8, geo.size.width * CGFloat(drinkDisplay) / CGFloat(perDrink)), height: 8)
                            .opacity(drinkDisplay > 0 ? 1 : 0)
                    }
                }
                .frame(height: 8)
                Text(appState.referralDrinksEarned > 0
                     ? "\(drinkDisplay)/\(perDrink) para tu próxima bebida ☕️"
                     : "\(drinkDisplay)/\(perDrink) para tu bebida ☕️")
                    .font(.caption)
                    .foregroundStyle(Color.echoTextSecondary)
            }

            HStack(spacing: 16) {
                statPill(value: completed, label: "completados")
                statPill(value: appState.pendingReferralCount, label: "en proceso")
                statPill(value: appState.referralDrinksEarned, label: appState.referralDrinksEarned == 1 ? "bebida ganada" : "bebidas ganadas")
            }

            if appState.pendingReferralCount > 0 {
                Text("Los que están \"en proceso\" ya se registraron — solo falta que publiquen su primer echo. ¡Recuérdales! 👀")
                    .font(.caption)
                    .foregroundStyle(Color.echoTextSecondary)
            }
        }
        .padding(18)
        .background(Color.echoCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func milestoneRow(emoji: String, target: Int, title: String, subtitle: String, achieved: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(achieved ? AccentColor.gold.color.opacity(0.25) : Color.echoVoteCircle)
                    .frame(width: 42, height: 42)
                Text(emoji)
                    .font(.system(size: 20))
                    .grayscale(achieved ? 0 : 0.9)
                    .opacity(achieved ? 1 : 0.6)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(target) referido\(target == 1 ? "" : "s")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(achieved ? AccentColor.gold.color : Color.echoGreen)
                    Text("·")
                        .foregroundStyle(Color.echoTextTertiary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.echoText)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.echoTextSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: achieved ? "checkmark.circle.fill" : "circle")
                .font(.body)
                .foregroundStyle(achieved ? Color.echoGreen : Color.echoTextTertiary)
        }
    }

    private func statPill(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.echoText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.echoTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var rewardsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tus bebidas")
                .font(.headline)
                .foregroundStyle(Color.echoText)
            ForEach(Array(appState.myReferralRewards.enumerated()), id: \.element.id) { index, reward in
                HStack(spacing: 10) {
                    Text("🏆")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bebida #\(appState.myReferralRewards.count - index)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.echoText)
                        Text(reward.status == .delivered ? "Entregada ✅" : "Pendiente de entrega — te contactamos pronto")
                            .font(.caption)
                            .foregroundStyle(reward.status == .delivered ? Color.echoGreen : Color.echoTextSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(Color.echoCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Cómo funciona?")
                .font(.headline)
                .foregroundStyle(Color.echoText)
            stepRow(number: "1", icon: "square.and.arrow.up", text: "Comparte tu código con amig@s de tu campus.")
            stepRow(number: "2", icon: "envelope.badge.shield.half.filled", text: "Se registran en Echo con su correo institucional y ponen tu código cuando la app les pregunte quién los invitó.")
            stepRow(number: "3", icon: "plus.bubble", text: "Cuando publiquen su primer echo, sumas 1 referido: 1 = badge OG 🐿️, \(AppState.referralGoldProfileAt) = perfil dorado ✨, \(perDrink) = bebida gratis ☕️ (y cada \(perDrink) después, otra).")
        }
        .padding(18)
        .background(Color.echoCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stepRow(number: String, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.echoGreen.opacity(0.18))
                    .frame(width: 30, height: 30)
                Text(number)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.echoGreen)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var claimEntryButton: some View {
        Button {
            showClaimSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ticket")
                Text("¿Te invitó un amig@? Ingresa su código")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(Color.echoGreen)
            .padding(14)
            .background(Color.echoGreen.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Claim sheet ("¿Quién te invitó?")

/// Shown once to fresh accounts after onboarding (and reachable from InviteFriendsView).
/// Server enforces the rules; this sheet just collects the code.
struct ReferralClaimSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var claimed = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if claimed {
                    successContent
                } else {
                    entryContent
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.echoBackground)
            .navigationTitle("¿Quién te invitó?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(claimed ? "Cerrar" : "Omitir") {
                        appState.markReferralPromptSeen()
                        dismiss()
                    }
                    .foregroundStyle(Color.echoTextSecondary)
                }
            }
            .onAppear {
                if let pending = appState.pendingInviteCode {
                    code = pending
                }
                codeFocused = true
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private var entryContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Si un amig@ te invitó a Echo, ingresa su código y ayúdale a ganarse un café ☕️")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .lineSpacing(2)

            TextField("ABC123", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .kerning(3)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.echoCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($codeFocused)
                .onChange(of: code) { _, newValue in
                    let cleaned = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                    code = String(cleaned.prefix(6))
                }

            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.echoOrange)
            }

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).padding(.vertical, 14)
                } else {
                    Text("Confirmar")
                        .fontWeight(.semibold)
                        .foregroundStyle(code.count == 6 ? .black : Color.echoTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(code.count == 6 ? Color.echoGreen : Color.echoCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(isSubmitting || code.count != 6)
        }
    }

    private var successContent: some View {
        VStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 56))
            Text("¡Listo!")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.echoText)
            Text("Registramos a tu amig@. Publica tu primer echo para que su referido cuente — y de paso estrena la app 😉")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        guard let status = await appState.claimReferralCode(code) else {
            errorMessage = "No se pudo conectar. Intenta de nuevo."
            return
        }
        if status == .ok {
            appState.markReferralPromptSeen()
            withAnimation { claimed = true }
        } else {
            errorMessage = status.errorMessage
            // These states are final — no point re-prompting this user later.
            if status == .alreadyReferred || status == .accountTooOld {
                appState.markReferralPromptSeen()
            }
        }
    }
}

#Preview {
    InviteFriendsView()
        .environmentObject(AppState())
}
