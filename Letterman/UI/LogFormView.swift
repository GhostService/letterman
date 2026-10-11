import SwiftUI

/// New log, or edit an unsigned one. Signed logs are locked by the server and never reach this screen.
struct LogFormView: View {
    @Environment(VolunteerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let existing: HourLog?
    @State private var draft: LogDraft
    @State private var signing = false
    @State private var saving = false
    @State private var error: String?
    @State private var savedOffline = false

    /// `draft` prefills a new log, e.g. from a shift the student signed up for.
    init(existing: HourLog?, draft: LogDraft? = nil) {
        self.existing = existing
        _draft = State(initialValue: draft ?? existing.map(LogDraft.init) ?? LogDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Where") {
                    TextField("Place name", text: $draft.placeName).textContentType(.organizationName)
                    TextField("Address", text: $draft.address).textContentType(.fullStreetAddress)
                }
                Section("When") {
                    DatePicker("Started", selection: $draft.startedAt, in: ...Date().addingTimeInterval(86400))
                    Stepper(value: $draft.hours, in: 0.5...24, step: 0.5) {
                        HStack {
                            Text("Hours")
                            Spacer()
                            Text(draft.hours.hoursText).font(.display(26, relativeTo: .title3)).foregroundStyle(Theme.ink)
                        }
                    }
                }
                Section("Comments") {
                    TextField("What did you do? (optional)", text: $draft.comments, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    signatureCell
                } header: {
                    Text("Supervisor signature")
                } footer: {
                    Text("A signature is required before these hours count. Once signed, the entry is locked.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.chalk)
            .navigationTitle(existing == nil ? "Log hours" : "Edit log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(Theme.link) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.bold().tint(Theme.link).disabled(!canSave)
                }
            }
            .fullScreenCover(isPresented: $signing) {
                SignatureSheet(summary: summary) { png, name in
                    draft.signaturePNG = png
                    draft.signerName = name
                }
            }
            .errorAlert($error)
            .alert("Saved on your phone", isPresented: $savedOffline) {
                Button("OK") { dismiss() }
            } message: {
                Text("There's no connection right now. This entry, including the signature, will upload automatically when you're back online.")
            }
        }
        .interactiveDismissDisabled(draft.signaturePNG != nil)
    }

    @ViewBuilder private var signatureCell: some View {
        if let png = draft.signaturePNG, let image = UIImage(data: png) {
            VStack(alignment: .leading, spacing: 8) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 90)
                    .accessibilityLabel("Signature by \(draft.signerName)")
                SignedPatch(signer: draft.signerName)
                Button("Remove signature", role: .destructive) {
                    draft.signaturePNG = nil
                    draft.signerName = ""
                }
                .font(.fig(15, .semibold))
            }
            .padding(.vertical, 4)
        } else {
            Button { signing = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "signature").font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.forest)
                        .frame(width: 46, height: 46).background(Circle().fill(Theme.gold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get supervisor signature").font(.fig(17, .bold)).foregroundStyle(.white)
                        Text(draft.placeName.trimmed.isEmpty ? "Add the place name first" : "Hand your phone to the person in charge")
                            .font(.fig(13)).foregroundStyle(Theme.heroText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.forest, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            .disabled(draft.placeName.trimmed.isEmpty)
        }
    }

    private var summary: String {
        "\(draft.hours.hoursText) \(draft.hours == 1 ? "hour" : "hours") at \(draft.placeName.trimmed) on \(draft.startedAt.formatted(date: .complete, time: .omitted)), starting at \(draft.startedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var canSave: Bool { !draft.placeName.trimmed.isEmpty && !saving }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            switch try await store.saveLog(draft, existingID: existing?.id) {
            case .uploaded: dismiss()
            case .savedOffline: savedOffline = true
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
