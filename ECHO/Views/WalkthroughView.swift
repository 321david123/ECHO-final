//
//  WalkthroughView.swift
//  ECHO
//

import SwiftUI

struct WalkthroughView: View {
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    private let steps: [WalkthroughStep] = [
        WalkthroughStep(
            icon: "bubble.left.and.bubble.right.fill",
            title: "Bienvenido a Echo",
            body: "Es un espacio anónimo solo para tu campus donde puedes preguntar cosas a la comunidad y ver qué es lo que está pasando 👀",
            buttonLabel: "¿Y qué puedo hacer?"
        ),
        WalkthroughStep(
            icon: "plus.circle.fill",
            title: "Publica un Echo",
            body: "Toca el botón verde con el \"+\" en la esquina inferior derecha para publicar lo que quieras. Pregunta algo, comparte un dato, desahógate. Todo es completamente anónimo.",
            buttonLabel: "¿Qué más?"
        ),
        WalkthroughStep(
            icon: "paperplane.fill",
            title: "Mensajes directos",
            body: "Desde cualquier post puedes enviarle un mensaje directo al autor sin que nadie más lo vea. Encuéntralos en la pestaña \"Mensajes\".",
            buttonLabel: "Casi listo..."
        ),
        WalkthroughStep(
            icon: "arrow.up.heart.fill",
            title: "Tu perfil y karma",
            body: "En la pestaña \"Perfil\" puedes ver tu karma. Cada voto positivo que recibes en tus echos suma karma. ¡Comparte cosas que le sirvan a tu comunidad!",
            buttonLabel: "¡Empezar!"
        )
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    stepDots

                    Image(systemName: steps[currentStep].icon)
                        .font(.system(size: 48))
                        .foregroundStyle(Color.echoGreen)
                        .frame(height: 56)

                    VStack(spacing: 12) {
                        Text(steps[currentStep].title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.echoText)
                            .multilineTextAlignment(.center)

                        Text(steps[currentStep].body)
                            .font(.subheadline)
                            .foregroundStyle(Color.echoTextSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 4)

                    Button {
                        advance()
                    } label: {
                        Text(steps[currentStep].buttonLabel)
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .background(Color.echoGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(28)
                .background(Color.echoCard)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: Color.echoGreen.opacity(0.08), radius: 24, x: 0, y: 8)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private var stepDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentStep ? Color.echoGreen : Color.echoTextTertiary.opacity(0.4))
                    .frame(width: index == currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
    }

    private func advance() {
        if currentStep < steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                isPresented = false
            }
        }
    }
}

private struct WalkthroughStep {
    let icon: String
    let title: String
    let body: String
    let buttonLabel: String
}

#Preview {
    WalkthroughView(isPresented: .constant(true))
}
