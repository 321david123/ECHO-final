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
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.echoGreen.opacity(0.3))
                                .frame(width: 64, height: 64)
                            Text(String((appState.verifiedCampus ?? appState.selectedCampus).shortName.prefix(1)))
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.echoGreen)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Anónimo")
                                .font(.headline)
                                .foregroundStyle(Color.echoText)
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
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.echoCard)
                .listRowSeparator(.hidden)
                
                Section("Cuenta") {
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
                Text("Versión 1.0")
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

#Preview {
    let state = AppState()
    state.hasCompletedOnboarding = true
    state.verifiedCampus = Campus.mexicanUniversities[0]
    return ProfileView()
        .environmentObject(state)
}
