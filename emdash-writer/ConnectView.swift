import SwiftUI

struct ConnectView: View {
    @Bindable var model: AppModel

    var body: some View {
        SiteForm(model: model, showsDisconnect: false)
            .formStyle(.grouped)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SiteForm: View {
    @Bindable var model: AppModel
    var showsDisconnect: Bool
    @State private var site = ""
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                TextField("Site", text: $site, prompt: Text("https://example.com"))
                SecureField("Token", text: $token, prompt: Text(model.isConnected ? "Stored in Keychain" : "API token"))
            } footer: {
                Text("Create the token in the EmDash admin, under Settings.")
            }
            if !model.notice.isEmpty && !model.isConnected {
                Text(model.notice)
                    .foregroundStyle(.red)
            }
            HStack {
                Button(model.busy ? "Connecting…" : "Connect") {
                    Task { await model.connect(site: site, token: token) }
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
                if showsDisconnect && model.isConnected {
                    Button("Disconnect", role: .destructive) {
                        model.disconnect()
                        token = ""
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
                if model.isConnected {
                    Button("Open Site") { model.openSite() }
                        .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if site.isEmpty {
                site = model.siteURL?.absoluteString ?? ""
            }
        }
    }
}
