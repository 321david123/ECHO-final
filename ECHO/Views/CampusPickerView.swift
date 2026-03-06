//
//  CampusPickerView.swift
//  ECHO
//

import SwiftUI

struct CampusPickerView: View {
    @Binding var selected: Campus
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(Campus.mexicanUniversities) { campus in
                Button {
                    selected = campus
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(campus.name)
                                .font(.body)
                                .foregroundStyle(Color.echoText)
                            Text(campus.city)
                                .font(.caption)
                                .foregroundStyle(Color.echoTextSecondary)
                        }
                        Spacer()
                        if campus.id == selected.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.echoGreen)
                        }
                    }
                }
                .listRowBackground(Color.echoCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.echoBackground)
            .navigationTitle("Tu campus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    CampusPickerView(selected: .constant(Campus.mexicanUniversities[0]))
}
