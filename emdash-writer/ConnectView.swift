import SwiftUI

struct ConnectView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Emd")
                    .font(.title2.weight(.semibold))
                Text("Connect an EmDash site to start writing.")
                    .foregroundStyle(.secondary)
            }
            SiteForm(model: model, showsSite: false)
                .frame(height: 230)
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SiteForm: View {
    @Bindable var model: AppModel
    /// Settings shows the connected site above the fields. The first-run screen has nothing to show yet.
    var showsSite: Bool
    @State private var site = ""
    @State private var token = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if showsSite && model.isConnected {
                    SiteCard(model: model, token: $token)
                }
                siteFields
            }
            .formStyle(.grouped)
            actionBar
        }
        .onAppear(perform: prefillSite)
    }

    private var siteFields: some View {
        Section {
            TextField("Site", text: $site, prompt: Text("https://example.com"))
            SecureField("Token", text: $token, prompt: Text(model.isConnected ? "Stored in Keychain" : "API token"))
        } header: {
            Text(model.isConnected ? "Switch site or token" : "Site")
        } footer: {
            Text("Create a token in the EmDash admin, under Settings.")
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            noticeLine
            Spacer(minLength: 0)
            if model.busy {
                ProgressView()
                    .controlSize(.small)
            }
            connectButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var noticeLine: some View {
        if !model.notice.isEmpty && !model.isConnected {
            Label(model.notice, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
        }
    }

    private var connectButton: some View {
        Button(model.isConnected ? "Reconnect" : "Connect") {
            let typed = token.trimmingCharacters(in: .whitespaces)
            let stored = typed.isEmpty
            Task {
                await model.connect(site: site, token: stored ? KeychainStore.load() ?? "" : typed, storeToken: !stored)
            }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!canConnect)
    }

    private var canConnect: Bool {
        let hasToken = !token.trimmingCharacters(in: .whitespaces).isEmpty || model.isConnected || model.offline
        return !model.busy && !site.trimmingCharacters(in: .whitespaces).isEmpty && hasToken
    }

    private func prefillSite() {
        guard site.isEmpty else { return }
        site = model.siteURL?.absoluteString ?? ""
    }
}

/// The connected site, with the two things you do to it.
private struct SiteCard: View {
    var model: AppModel
    @Binding var token: String
    @State private var confirmingDisconnect = false

    var body: some View {
        Section {
            HStack(spacing: 12) {
                badge
                identity
                Spacer(minLength: 8)
                actions
            }
            .padding(.vertical, 4)
        }
    }

    private var badge: some View {
        Image(systemName: "globe")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.siteTitle.isEmpty ? host : model.siteTitle)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("Connected to \(host)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Open Site", systemImage: "arrow.up.right.square") { model.openSite() }
                .labelStyle(.titleOnly)
            Button("Disconnect", role: .destructive) { confirmingDisconnect = true }
                .disabled(model.busy)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .confirmationDialog("Disconnect from \(host)?", isPresented: $confirmingDisconnect) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await model.save()
                    model.disconnect()
                    token = ""
                }
            }
        } message: {
            Text("The token is removed from the Keychain. Posts on the site are not affected.")
        }
    }

    private var host: String {
        model.siteURL?.host ?? "your site"
    }
}
