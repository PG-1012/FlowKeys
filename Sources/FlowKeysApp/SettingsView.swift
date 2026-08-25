import FlowKeysCore
import SwiftUI

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

            Toggle("Restore previous clipboard after pasting", isOn: restoreClipboard)
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

    private var delayLabel: String {
        String(format: "%.2fs", preferences.revealDelay)
    }

    private func push() {
        preferences.save()
        onChange(preferences)
    }
}
