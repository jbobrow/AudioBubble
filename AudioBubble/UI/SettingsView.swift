import SwiftUI

/// Your name and color, debug mode, and the introduction again.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DebugSettings.key) private var debugMode = false
    @State private var name = ""
    @State private var hue = 0.58
    @State private var showsIntro = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        BubbleAvatar(name: name.isEmpty ? "?" : name, hue: hue, size: 96)
                            .animation(.snappy, value: hue)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                    ColorSwatches(hue: $hue)
                        .padding(.vertical, 6)
                } header: {
                    Text("You")
                } footer: {
                    Text("People nearby see your name and color.")
                }

                Section {
                    Button("How Audio Bubble works") { showsIntro = true }
                }

                Section {
                    Toggle("Debug mode", isOn: $debugMode)
                } footer: {
                    Text("Shows latency, connection and echo details in your bubble.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Background())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = model.identity?.name ?? ""
            hue = model.identity?.hue ?? hue
        }
        .onDisappear(perform: save)
        .fullScreenCover(isPresented: $showsIntro) {
            ZStack {
                Background()
                IntroPages(finishTitle: "Done") { showsIntro = false }
            }
        }
    }

    private func save() {
        model.updateIdentity(name: name, hue: hue)
    }
}
