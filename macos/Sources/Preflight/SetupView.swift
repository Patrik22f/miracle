import SwiftUI

struct SetupView: View {
    @Bindable var settings: AppSettings
    let onboarding: Bool
    private var permissionGranted: Bool { settings.permissionGranted }
    let complete: () -> Void
    let changed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(onboarding ? "A little help, on your terms." : "How Preflight appears")
                        .font(.title2.bold())
                    Text("The right skills, before you send.").foregroundStyle(.secondary)
                }
            }
            Text("Choose how recommendations find you.").font(.headline)
            HStack(alignment: .top, spacing: 14) {
                ForEach(DisplayMode.allCases) { mode in
                    Button {
                        settings.mode = mode
                        changed()
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            ModePreview(mode: mode)
                            HStack {
                                Label(mode.title, systemImage: mode.symbol).font(.headline)
                                Spacer()
                                Image(systemName: settings.mode == mode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(settings.mode == mode ? Color.accentColor : Color.secondary)
                            }
                            Text(mode.summary).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).frame(height: 55, alignment: .top)
                        }
                        .padding(16)
                        .background(settings.mode == mode ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(settings.mode == mode ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: settings.mode == mode ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mode.title). \(mode.summary)")
                    .accessibilityAddTraits(settings.mode == mode ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Recommend automatically as I write", isOn: $settings.automatic)
                    .onChange(of: settings.automatic) { changed() }
                Text("Works with accessible prompt fields in Cursor. Recommendations update after a short pause in typing. In other apps, use ⌥⌘Return or paste your prompt.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label(permissionGranted ? "Accessibility is enabled" : "Allow access to your prompt", systemImage: permissionGranted ? "checkmark.circle.fill" : "hand.raised")
                    Spacer()
                    if !permissionGranted {
                        Button("Enable Accessibility…", action: FocusedText.requestPermission)
                    }
                }
                if permissionGranted {
                    Text(settings.monitoringStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("Preflight reads the focused prompt to suggest skills. Your prompt stays on your Mac; only topic labels go to skills.sh.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text(permissionGranted ? "You can change this anytime from the menu bar." : "You can also paste a prompt manually.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(onboarding ? "Start using Preflight" : "Done", action: complete)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 610)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ModePreview: View {
    let mode: DisplayMode
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(.tertiary).frame(width: 5, height: 5)
                Circle().fill(.tertiary).frame(width: 5, height: 5)
                Spacer()
                Image(systemName: "sparkle").font(.caption)
                Circle().fill(mode == .stealth ? Color.accentColor : Color.clear).frame(width: 5, height: 5)
            }.padding(10).background(.quaternary.opacity(0.4))
            Spacer(minLength: 8)
            if mode == .helpful {
                Label("A skill for this prompt", systemImage: "sparkles")
                    .font(.caption).padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 12)
            }
            HStack {
                Text("Ask anything…").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(.tertiary)
            }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 7)).padding(12)
        }
        .frame(height: 126).background(.background, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator.opacity(0.5)))
        .accessibilityHidden(true)
    }
}
