import SwiftUI

@main
struct MatisseConnectorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var transfer = TransferModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Collegamento al PC") {
                    TextField("http://indirizzo-del-pc:porta", text: $transfer.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Ricevi elementi selezionati") {
                        Task { await transfer.receive() }
                    }
                    .disabled(transfer.running)
                }
                Section("Stato") {
                    Text(transfer.status)
                    ForEach(transfer.results) { result in
                        Label(result.text, systemImage: result.success ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(result.success ? .green : .orange)
                    }
                }
                Section {
                    Text("Foto e video vengono aggiunti a Foto. Documenti e musica sono salvati in File; iOS non consente a questa app di inserirli nella libreria Apple Music.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Matisse")
        }
    }
}
