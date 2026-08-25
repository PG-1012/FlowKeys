import AppKit
import FlowKeysCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings window. Changes apply immediately — there is no Apply button and
/// nothing to confirm, which suits an app you only open to change one thing.
///
/// Note the explicitly-typed `Binding` helpers below. Inlining them into the
/// view body makes SwiftUI's type-checker give up ("unable to type-check this
/// expression in reasonable time"); naming them keeps each one trivial.
struct SettingsView: View {
    @State var preferences: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled
    let onChange: (Preferences) -> Void

    // MARK: - Bindings

    private var capacity: Binding<Double> {
        Binding(
            get: { Double(preferences.historyCapacity) },
            set: { newValue in
                preferences.historyCapacity = Int(newValue)
                push()
            }
        )
    }

    private var forgetAfterDays: Binding<Int> {
        Binding(
            get: { preferences.forgetAfterDays },
            set: { newValue in
                preferences.forgetAfterDays = newValue
                push()
            }
        )
    }

    private var persistHistory: Binding<Bool> {
        Binding(
            get: { preferences.persistHistory },
            set: { newValue in
                preferences.persistHistory = newValue
                push()
            }
        )
    }

    private var revealDelay: Binding<Double> {
        Binding(
            get: { preferences.revealDelay },
            set: { newValue in
                preferences.revealDelay = newValue
                push()
            }
        )
    }

    private var pasteMethod: Binding<PasteMethod> {
        Binding(
            get: { preferences.pasteMethod },
            set: { newValue in
                preferences.pasteMethod = newValue
                push()
            }
        )
    }

    private var restoreDelay: Binding<Double> {
        Binding(
            get: { preferences.restoreDelay },
            set: { newValue in
                preferences.restoreDelay = newValue
                push()
            }
        )
    }

    private var restoreClipboard: Binding<Bool> {
        Binding(
            get: { preferences.restoreClipboardAfterPaste },
            set: { newValue in
                preferences.restoreClipboardAfterPaste = newValue
                push()
            }
        )
    }

    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                LoginItem.setEnabled(newValue)
                launchAtLogin = LoginItem.isEnabled
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Form {
            historySection
            pastingSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var historySection: some View {
        Section("History") {
            LabeledContent("Keep") {
                HStack {
                    Slider(value: capacity, in: capacityBounds, step: 5)
                    Text("\(preferences.historyCapacity) items")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }

            Picker("Forget after", selection: forgetAfterDays) {
                Text("Never").tag(0)
                Text("1 day").tag(1)
                Text("1 week").tag(7)
                Text("30 days").tag(30)
            }

            Toggle("Remember history between launches", isOn: persistHistory)
            caption("Stored unencrypted in your home folder, readable only by your account.")
        }
    }

    private var pastingSection: some View {
        Section("Pasting") {
            LabeledContent("Show list after") {
                HStack {
                    Slider(value: revealDelay, in: delayBounds)
                    Text(delayLabel)
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
            caption("How long to hold ⌘V before the list appears on its own. A quick tap still pastes instantly.")

            Picker("Deliver text by", selection: pasteMethod) {
                ForEach(PasteMethod.allCases, id: \.self) { method in
                    Text(method.title).tag(method)
                }
            }
            caption(pasteMethodHelp)

            typedAppsList

            Toggle("Restore previous clipboard after pasting", isOn: restoreClipboard)

            if preferences.restoreClipboardAfterPaste && preferences.pasteMethod == .keystroke {
                LabeledContent("Restore after") {
                    HStack {
                        Slider(value: restoreDelay, in: restoreBounds)
                        Text(restoreLabel)
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                caption("Increase this if an app pastes the wrong item — some apps read the clipboard lazily.")
            }
        }
    }

    /// Apps that always get typed text, regardless of the default above.
    private var typedAppsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Always type in these apps")
                .font(.subheadline.weight(.medium))
            Text("Some apps ignore a synthetic ⌘V however faithfully it is sent. There is no way to detect that automatically, so they are listed here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if preferences.typedApps.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedTypedApps, id: \.self) { bundleID in
                    HStack(spacing: 6) {
                        Text(Self.displayName(for: bundleID))
                            .font(.callout)
                        Text(bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            preferences.typedApps.remove(bundleID)
                            push()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Button("Add App…") { addApp() }
                .controlSize(.small)
        }
    }

    private var sortedTypedApps: [String] {
        preferences.typedApps.sorted { Self.displayName(for: $0) < Self.displayName(for: $1) }
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier
        else { return }
        preferences.typedApps.insert(id)
        push()
    }

    private var pasteMethodHelp: String {
        switch preferences.pasteMethod {
        case .keystroke:
            return "Fastest, and keeps formatting the app would normally apply. If an app ignores it — Microsoft Word sometimes does — try typing instead."
        case .typed:
            return "Types the characters directly. Slower and plain text only, but works in apps that ignore a synthetic ⌘V. Your clipboard is left untouched."
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Open at login", isOn: openAtLogin)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var capacityBounds: ClosedRange<Double> {
        Double(Preferences.capacityRange.lowerBound)...Double(Preferences.capacityRange.upperBound)
    }

    private var delayBounds: ClosedRange<Double> {
        Preferences.revealDelayRange
    }

    private var restoreBounds: ClosedRange<Double> {
        Preferences.restoreDelayRange
    }

    private var restoreLabel: String {
        String(format: "%.2fs", preferences.restoreDelay)
    }

    private var delayLabel: String {
        String(format: "%.2fs", preferences.revealDelay)
    }

    private func push() {
        preferences.save()
        onChange(preferences)
    }
}
