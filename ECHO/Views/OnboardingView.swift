//
//  OnboardingView.swift
//  ECHO
//

import SwiftUI

/// Onboarding: with Supabase = campus → email → send OTP → code → verify. Without = campus → Entrar (anonymous).
struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var emailFieldFocused: Bool
    @FocusState private var codeFieldFocused: Bool
    @State private var step: Step = .campus
    @State private var selectedCampus: Campus = Campus.mexicanUniversities[0]
    @State private var email = ""
    @State private var code = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var errorMessage: String?
    
    private enum Step {
        case campus
        case email
        case code
    }
    
    /// With Supabase or after sign-out, user must do full OTP (campus → email → code); never "Entrar" without verification.
    private var useOTP: Bool { appState.useSupabase || appState.requiresReauthAfterSignOut }
    
    var body: some View {
        ZStack {
            Color.echoBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if useOTP {
                    stepIndicator
                }
                Group {
                    switch step {
                    case .campus: selectCampusStep
                    case .email: enterEmailStep
                    case .code: enterCodeStep
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach([Step.campus, .email, .code], id: \.hashValue) { s in
                Circle()
                    .fill(step == s ? Color.echoGreen : Color.echoTextTertiary.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 12)
    }
    
    private var selectCampusStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("¿En qué universidad estudias?")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.echoText)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            
            Text(useOTP ? "Elige tu campus. Luego verificamos tu correo institucional." : "Elige tu campus para ver el feed.")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .padding(.horizontal, 24)
            
            List(Campus.mexicanUniversities) { campus in
                Button {
                    selectedCampus = campus
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(campus.name)
                                .font(.body)
                                .foregroundStyle(Color.echoText)
                            Text(campus.city)
                                .font(.caption)
                                .foregroundStyle(Color.echoTextSecondary)
                        }
                        Spacer()
                        if campus.id == selectedCampus.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.echoGreen)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.echoCard)
                .listRowSeparatorTint(Color.echoTextTertiary.opacity(0.3))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.echoOrange)
                    .padding(.horizontal, 24)
            }
            
            Button {
                if useOTP {
                    step = .email
                    errorMessage = nil
                } else {
                    Task { await enterAnonymous() }
                }
            } label: {
                if !useOTP && isVerifying {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    Text(useOTP ? "Continuar" : "Entrar")
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(Color.echoGreen)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(!useOTP && isVerifying)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.echoBackground)
    }
    
    private var enterEmailStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                step = .campus
                email = ""
                errorMessage = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Cambiar campus")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.echoGreen)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            Text("Correo institucional")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.echoText)
                .padding(.horizontal, 24)
            
            Text("Usa tu correo de \(selectedCampus.name) (ej. @\(selectedCampus.allowedEmailDomains.first ?? "tec.mx"))")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .padding(.horizontal, 24)
            
            TextField("correo@\(selectedCampus.allowedEmailDomains.first ?? "tec.mx")", text: $email)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .padding()
                .background(Color.echoCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .focused($emailFieldFocused)
            
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.echoOrange)
                    .padding(.horizontal, 24)
            }
            
            Button {
                Task { await sendCode() }
            } label: {
                if isSending {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    Text("Enviar código")
                        .fontWeight(.semibold)
                        .foregroundStyle(emailValidForStep ? .black : Color.echoTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(emailValidForStep ? Color.echoGreen : Color.echoCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(isSending || !emailValidForStep)
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(Color.echoBackground)
        .onAppear {
            if step == .email { emailFieldFocused = true }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .email { emailFieldFocused = true }
            if newStep == .code { codeFieldFocused = true }
        }
    }
    
    private var emailValidForStep: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let reviewer = SupabaseConfig.reviewerEmail, trimmed == reviewer.lowercased() { return true }
        return selectedCampus.allows(email: trimmed)
    }
    
    private var enterCodeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                step = .email
                code = ""
                errorMessage = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Cambiar correo")
                        .font(.subheadline)
                }
                .foregroundStyle(Color.echoGreen)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            Text("Código de verificación")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.echoText)
                .padding(.horizontal, 24)
            
            Text("Revisa tu correo \(email). Introduce el código de 6 dígitos.")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .padding(.horizontal, 24)
            
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.echoCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .focused($codeFieldFocused)
                .onChange(of: code) { _, newValue in
                    if newValue.count > 6 { code = String(newValue.prefix(6)) }
                }
            
            if let msg = errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color.echoOrange)
                    .padding(.horizontal, 24)
            }
            
            Button {
                Task { await verifyAndEnter() }
            } label: {
                if isVerifying {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).padding(.vertical, 16)
                } else {
                    Text("Entrar")
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .background(Color.echoGreen)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(isVerifying || code.trimmingCharacters(in: .whitespacesAndNewlines).count != 6)
            .padding(.horizontal, 24)
            
            HStack {
                Spacer(minLength: 0)
                Button {
                    Task { await sendCode() }
                } label: {
                    Text("Reenviar código")
                        .font(.subheadline)
                        .foregroundStyle(Color.echoGreen)
                }
                .disabled(isSending)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .background(Color.echoBackground)
    }
    
    private func sendCode() async {
        errorMessage = nil
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        if let reviewer = SupabaseConfig.reviewerEmail, trimmed == reviewer.lowercased() {
            await MainActor.run { step = .code; errorMessage = nil; codeFieldFocused = true }
            return
        }
        guard selectedCampus.allows(email: trimmed) else {
            await MainActor.run { errorMessage = "Usa un correo de tu universidad." }
            return
        }
        await MainActor.run { isSending = true }
        defer { Task { @MainActor in isSending = false } }
        do {
            try await appState.sendOTP(email: trimmed, campusId: selectedCampus.id)
            await MainActor.run { step = .code; errorMessage = nil; codeFieldFocused = true }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func verifyAndEnter() async {
        errorMessage = nil
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedCode.isEmpty, !trimmedEmail.isEmpty else { return }
        if let reviewer = SupabaseConfig.reviewerEmail,
           trimmedEmail == reviewer.lowercased(),
           trimmedCode == SupabaseConfig.reviewerCode {
            await MainActor.run {
                appState.completeReviewerOnboarding(campus: selectedCampus)
            }
            return
        }
        await MainActor.run { isVerifying = true }
        defer { Task { @MainActor in isVerifying = false } }
        do {
            try await appState.enterWithEmailOTP(campus: selectedCampus, email: trimmedEmail, code: trimmedCode)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
    
    private func enterAnonymous() async {
        errorMessage = nil
        await MainActor.run { isVerifying = true }
        defer { Task { @MainActor in isVerifying = false } }
        do {
            try await appState.enterWithCampus(selectedCampus)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
