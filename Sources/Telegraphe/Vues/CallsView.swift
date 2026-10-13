import SwiftUI

struct CallsView: View {
    @State var selectedSegment = "Tous"
    var body: some View {
        NavigationStack {
            VStack(spacing: TelegrapheTheme.spaceXL) {
                Picker("Filtre des appels", selection: $selectedSegment) {
                    Text("Tous").tag("Tous")
                    Text("Manqués").tag("Manqués")
                }.pickerStyle(.segmented)
                Spacer()
                EmptyStateView(title: "Les appels arrivent bientôt",
                               message: "Les appels audio et vidéo ne sont pas encore disponibles.",
                               symbol: "phone")
                Spacer()
            }
            .padding(TelegrapheTheme.spaceL)
            .background(TelegrapheTheme.background)
            .navigationTitle("Appels")
        }
    }
}
