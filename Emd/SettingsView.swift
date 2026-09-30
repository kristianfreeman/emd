import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            SiteForm(model: model, showsSite: true)
                .frame(width: 520, height: model.isConnected ? 330 : 250)
                .tabItem { Label("Site", systemImage: "globe") }
            WritingSettings(model: model)
                .frame(width: 520, height: 520)
                .tabItem { Label("Writing", systemImage: "textformat") }
        }
    }
}

private struct WritingSettings: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            typeSection
            focusSection
        }
        .formStyle(.grouped)
    }

    private var typeSection: some View {
        Section("Type") {
            Picker("Font", selection: font) {
                ForEach(WriterFont.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent("Size") {
                Stepper(value: size, in: 13...24, step: 1) {
                    Text("\(Int(model.fontSize)) pt")
                        .monospacedDigit()
                }
            }
        }
    }

    private var focusSection: some View {
        Section {
            LabeledContent("Depth") {
                Text(model.focusDepth.label)
                    .foregroundStyle(.secondary)
            }
            Slider(value: depth, in: 0...Double(FocusDepth.allCases.count - 1), step: 1) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: "circle.lefthalf.filled")
            } maximumValueLabel: {
                Image(systemName: "aqi.medium")
            }
            FocusPreview(depth: model.focusDepth, font: model.fontChoice, palette: Palette.resolve(colorScheme))
        } header: {
            Text("Focus")
        } footer: {
            Text("Turn Focus on with View › Focus (⇧⌘F), and Typewriter with View › Typewriter (⇧⌘T).")
                .foregroundStyle(.secondary)
        }
    }

    private var appearance: Binding<AppearanceChoice> {
        Binding(get: { model.appearance }, set: { model.setAppearance($0) })
    }

    private var font: Binding<WriterFont> {
        Binding(get: { model.fontChoice }, set: { model.setFont($0) })
    }

    private var size: Binding<Double> {
        Binding(get: { model.fontSize }, set: { model.setFontSize($0) })
    }

    private var depth: Binding<Double> {
        Binding(
            get: { Double(model.focusDepth.rawValue) },
            set: { model.focusDepth = FocusDepth(rawValue: Int($0.rounded())) ?? .muted }
        )
    }
}

/// Three lines on the writing paper: the caret line, and what focus does to its neighbors.
private struct FocusPreview: View {
    var depth: FocusDepth
    var font: WriterFont
    var palette: Palette

    private let size: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line("The morning light came in sideways through the blinds.", active: false)
            line("She wrote one sentence, and then the next one.", active: true)
            line("Somewhere below, a kettle started to sing.", active: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.hairline)
        }
        .animation(.easeOut(duration: 0.18), value: depth)
    }

    private func line(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(font.font(size: size))
            .lineLimit(1)
            .foregroundStyle(active ? palette.ink : dimmed)
            .blur(radius: active ? 0 : depth.blurRadius(fontSize: size))
    }

    private var dimmed: Color {
        Color(nsColor: depth.ink(muted: palette.nsMuted, paper: palette.nsPaper))
    }
}
