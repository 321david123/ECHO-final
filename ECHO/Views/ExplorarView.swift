//
//  ExplorarView.swift
//  ECHO
//

import SwiftUI

struct ExplorarView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.echoTextTertiary)
            Text("En construcción")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.echoText)
            Text("Estamos trabajando en esta sección.")
                .font(.subheadline)
                .foregroundStyle(Color.echoTextSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.echoBackground)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ExplorarView()
}
