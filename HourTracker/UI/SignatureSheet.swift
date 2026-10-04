import PencilKit
import SwiftUI

/// Full-screen sign-off the volunteer hands to their supervisor.
struct SignatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Session.self) private var session
    /// e.g. "4 hours at Lakeview Animal Shelter on Saturday, October 3, 2026, starting at 10:00 AM"
    let summary: String
    let onSign: (Data, String) -> Void
    @State private var signerName = ""
    @State private var drawing = PKDrawing()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Cancel") { dismiss() }.font(.fig(17, .semibold)).foregroundStyle(Theme.heroText)
                Spacer()
            }
            Text("Supervisor sign-off").font(.display(46)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text("\(session.user?.name ?? "This volunteer") volunteered \(summary).")
                .font(.fig(16)).foregroundStyle(Theme.heroText)
            DarkField(label: "Your full name", text: $signerName).textContentType(.name)

            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle().fill(Theme.forest).frame(height: 2).opacity(0.6)
                        Text("Sign above the line").font(.fig(13)).foregroundStyle(Color(hex: 0x5E6B63))
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 26)
                    SignatureCanvas(drawing: $drawing)
                        .accessibilityLabel("Signature area. Draw your signature with your finger.")
                }
                Button("Clear") { drawing = PKDrawing() }
                    .font(.fig(14, .bold)).foregroundStyle(Theme.forest)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color(hex: 0xEEF1EC)))
                    .padding(12)
            }
            .frame(maxHeight: .infinity)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))

            Button("Confirm and sign") {
                onSign(Self.png(from: drawing), signerName.trimmed)
                dismiss()
            }
            .buttonStyle(GoldButtonStyle())
            .disabled(!canSign)
            .opacity(canSign ? 1 : 0.5)
            Text("By signing you confirm these hours. Signed entries are locked and can't be changed.")
                .font(.fig(12.5)).foregroundStyle(Theme.heroMuted).frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Theme.forest.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    private var canSign: Bool { !signerName.trimmed.isEmpty && !drawing.strokes.isEmpty }

    /// Black ink on white, cropped to the signature. Always rendered in light mode so the ink never turns white.
    static func png(from drawing: PKDrawing) -> Data {
        let bounds = drawing.bounds.insetBy(dx: -16, dy: -16)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: bounds, scale: 2)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: bounds.size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            ink.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
    }
}

struct SignatureCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput // fingers, not just Apple Pencil
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let drawing: Binding<PKDrawing>
        init(drawing: Binding<PKDrawing>) { self.drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing.wrappedValue = canvasView.drawing }
    }
}
