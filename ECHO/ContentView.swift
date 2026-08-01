//
//  ContentView.swift
//  ECHO
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingCompose = false
    @State private var showingWalkthrough = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $appState.selectedTab) {
                FeedView()
                    .tabItem { Label("Inicio", systemImage: "house.fill") }
                    .tag(0)
                MessagesView()
                    .tabItem { Label("Mensajes", systemImage: "paperplane.fill") }
                    .tag(1)
                ExplorarView()
                    .tabItem { Label("Explorar", systemImage: "magnifyingglass") }
                    .tag(2)
                ProfileView()
                    .tabItem { Label("Perfil", systemImage: "person.fill") }
                    .tag(3)
            }
            .tint(.echoGreen)
            .preferredColorScheme(.dark)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(Color.echoBar)
                UITabBar.appearance().scrollEdgeAppearance = appearance
                UITabBar.appearance().standardAppearance = appearance
            }
            
            if appState.selectedTab == 0 {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.echoGreen)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 52)
            }

            if showingWalkthrough {
                WalkthroughView(isPresented: $showingWalkthrough)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingCompose) {
            ComposeView()
        }
        // "¿Quién te invitó?" — offered once to fresh accounts, after the walkthrough.
        .sheet(isPresented: Binding(
            get: { appState.shouldOfferReferralClaim && !showingWalkthrough },
            set: { if !$0 { appState.shouldOfferReferralClaim = false } }
        )) {
            ReferralClaimSheet()
                .environmentObject(appState)
        }
        .onAppear {
            if !appState.hasCompletedWalkthrough {
                showingWalkthrough = true
            }
        }
        .onChange(of: showingWalkthrough) { _, isShowing in
            if !isShowing {
                appState.completeWalkthrough()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
