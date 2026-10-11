import SwiftUI

struct LogDetailView: View {
    @Environment(VolunteerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let logID: String
    @State private var editing = false
    @State private var signing = false
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        if let log = store.logs.first(where: { $0.id == logID }) {
            content(log)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ log: HourLog) -> some View {
        HeroScreen {
            Text(log.startedAt.dayAndTime).font(.fig(15, .semibold)).foregroundStyle(Theme.heroText)
            HeroTitle(log.placeName, size: 46)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(log.hours.hoursText).font(.display(64)).foregroundStyle(Theme.gold)
                Text(log.hours == 1 ? "hour" : "hours").font(.display(28, relativeTo: .title2))
            }
        } content: {
            if !log.address.isEmpty || !log.comments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if !log.address.isEmpty { detail("Address", log.address) }
                    if !log.comments.isEmpty { detail("Comments", log.comments) }
                }
                .card()
            }

            SectionHeader("Supervisor signature")
            if log.isSigned {
                VStack(alignment: .leading, spacing: 10) {
                    if let image = log.signatureImage {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 140)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Signature by \(log.signerName)")
                    }
                    SignedPatch(signer: log.signerName, confirmed: log.isConfirmed)
                    if let date = log.signedDate {
                        Text("\(log.isConfirmed ? "Confirmed in Letterman" : "Signed") \(date.formatted(date: .abbreviated, time: .shortened)). This entry is locked.")
                            .font(.fig(13)).foregroundStyle(Theme.mute)
                    }
                }
                .card()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    NeedsSignatureBadge()
                    Text("These hours don't count until the person in charge signs.").font(.fig(15)).foregroundStyle(Theme.mute)
                    Button("Get supervisor signature") { signing = true }.buttonStyle(ForestButtonStyle())
                    Button("Edit details") { editing = true }.font(.fig(16, .semibold)).frame(maxWidth: .infinity).padding(.top, 2)
                }
                .card()
            }

            Button("Delete this log", role: .destructive) { confirmingDelete = true }
                .font(.fig(16, .semibold)).frame(maxWidth: .infinity).padding(.top, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .forestNavBar()
        .sheet(isPresented: $editing) { LogFormView(existing: log) }
        .fullScreenCover(isPresented: $signing) {
            SignatureSheet(summary: "\(log.hours.hoursText) \(log.hours == 1 ? "hour" : "hours") at \(log.placeName) on \(log.startedAt.formatted(date: .complete, time: .omitted)), starting at \(log.startedAt.formatted(date: .omitted, time: .shortened))") { png, name in
                var draft = LogDraft(log)
                draft.signaturePNG = png
                draft.signerName = name
                Task {
                    do {
                        if try await store.saveLog(draft, existingID: log.id) == .savedOffline {
                            notice = "No connection right now. The signature is saved on your phone and will upload when you're back online."
                        }
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        .confirmationDialog("Delete this log?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do { try await store.deleteLog(log) } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text(log.isSigned ? "The signature will be deleted too, and you'd need to get it signed again." : "This can't be undone.")
        }
        .errorAlert($error)
        .alert("Saved on your phone", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.fig(13, .semibold)).foregroundStyle(Theme.mute)
            Text(value).font(.fig(16)).foregroundStyle(Theme.ink)
        }
    }
}

extension HourLog: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
