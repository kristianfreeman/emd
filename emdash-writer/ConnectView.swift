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
            siteFields
            noticeLine
            connectionButtons
        }
        .onAppear(perform: prefillSite)
    }

    private var siteFields: some View {
        Section {
            TextField("Site", text: $site, prompt: Text("https://example.com"))
            SecureField("Token", text: $token, prompt: Text(model.isConnected ? "Stored in Keychain" : "API token"))
        } footer: {
            Text("Create the token in the EmDash admin, under Settings.")
        }
    }

    @ViewBuilder
    private var noticeLine: some View {
        if !model.notice.isEmpty && !model.isConnected {
            Text(model.notice)
                .foregroundStyle(.red)
        }
    }

    private var connectionButtons: some View {
        HStack {
            connectButton
            disconnectButton
            openSiteButton
        }
    }

    private var connectButton: some View {
        Button(model.busy ? "Connecting…" : "Connect") {
            Task { await model.connect(site: site, token: token) }
        }
        .buttonStyle(.plain)
        .disabled(model.busy)
    }

    @ViewBuilder
    private var disconnectButton: some View {
        if showsDisconnect && model.isConnected {
            Button("Disconnect", role: .destructive) {
                model.disconnect()
                token = ""
            }
            .buttonStyle(.plain)
            .disabled(model.busy)
        }
    }

    @ViewBuilder
    private var openSiteButton: some View {
        if model.isConnected {
            Button("Open Site") { model.openSite() }
                .buttonStyle(.plain)
        }
    }

    private func prefillSite() {
        guard site.isEmpty else { return }
        site = model.siteURL?.absoluteString ?? ""
    }
}
