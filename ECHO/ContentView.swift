//
//  ContentView.swift
//  ECHO
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showingCompose = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                FeedView()
                    .tabItem { Label("Inicio", systemImage: "house.fill") }
                    .tag(0)
                MessagesView()
                    .tabItem { Label("Mensajes", systemImage: "paperplane.fill") }
                    .tag(1)
                ProfileView()
                    .tabItem { Label("Perfil", systemImage: "person.fill") }
                    .tag(2)
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
            
            if selectedTab == 0 {
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
        }
        .sheet(isPresented: $showingCompose) {
            ComposeView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
