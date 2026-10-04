import SwiftUI

/// "Letterman" design: forest green + varsity gold (docs/designs/b-letterman.html).
enum Theme {
    static let forest = Color(hex: 0x123B2A)
    static let forest2 = Color(hex: 0x1B4D38)
    static let gold = Color(hex: 0xF2B33D)
    static let felt = Color(hex: 0xB8322A)
    static let heroText = Color(hex: 0xCFE0D6)
    static let heroMuted = Color(hex: 0x9DB5A8)
    // These adapt to dark mode.
    static let chalk = Color(light: 0xEEF1EC, dark: 0x0B1A12)
    static let card = Color(light: 0xFFFFFF, dark: 0x16281F)
    static let ink = Color(light: 0x0F1A14, dark: 0xEEF1EC)
    static let mute = Color(light: 0x5E6B63, dark: 0x9DB5A8)
    static let link = Color(light: 0x123B2A, dark: 0xF2B33D)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

enum Fig: String {
    case regular = "Figtree-Regular", medium = "Figtree-Medium", semibold = "Figtree-SemiBold", bold = "Figtree-Bold"
}

extension Font {
    /// Big condensed numbers and headlines. Scales with Dynamic Type.
    static func display(_ size: CGFloat, relativeTo style: TextStyle = .largeTitle) -> Font {
        .custom("BigShouldersDisplay-Black", size: size, relativeTo: style)
    }

    static func displayBold(_ size: CGFloat, relativeTo style: TextStyle = .title2) -> Font {
        .custom("BigShouldersDisplay-ExtraBold", size: size, relativeTo: style)
    }

    static func fig(_ size: CGFloat, _ weight: Fig = .regular, relativeTo style: TextStyle = .body) -> Font {
        .custom(weight.rawValue, size: size, relativeTo: style)
    }
}

// MARK: - Hero header

/// The forest-green header with the gold stripe used at the top of every main screen.
struct Hero<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .foregroundStyle(.white)
            // Extends up under the status bar and over-scroll so the top never shows a gap.
            .background(alignment: .bottom) { Theme.forest.frame(height: 2000) }
            .overlay(alignment: .bottom) { Stripe() }
    }
}

struct Stripe: View {
    var body: some View {
        Canvas { context, size in
            var x = 0.0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 18, height: size.height)), with: .color(Theme.gold))
                x += 26
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A scrolling screen with a hero on top and cards below.
struct HeroScreen<HeroContent: View, Content: View>: View {
    @ViewBuilder var hero: HeroContent
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Hero { hero }
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(16)
                    .padding(.bottom, 80)
            }
        }
        .background(Theme.chalk)
    }
}

struct HeroTitle: View {
    let text: String
    var size: CGFloat = 52

    init(_ text: String, size: CGFloat = 52) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.display(size))
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.displayBold(24)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

// MARK: - Cards, badges, buttons

extension View {
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Shows any error message in a standard alert.
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert("Couldn't finish that", isPresented: Binding(get: { message.wrappedValue != nil },
                                                           set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Forest nav bar with white text, used by pushed screens and sheets.
    func forestNavBar() -> some View {
        self.toolbarBackground(Theme.forest, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// The stitched gold "patch" that marks a signed log.
struct SignedPatch: View {
    let signer: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Theme.gold)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.forest))
                .overlay(Circle().inset(by: 2.5).strokeBorder(Theme.gold, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2])))
            Text("Signed by \(signer)").font(.fig(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.link)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NeedsSignatureBadge: View {
    var text = "Needs signature"

    var body: some View {
        Text(text)
            .font(.fig(12, .bold, relativeTo: .caption))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.felt, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fig(18, .bold, relativeTo: .headline))
            .foregroundStyle(Theme.forest)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.gold.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ForestButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.fig(17, .bold, relativeTo: .headline))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.forest.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Text field on a dark (forest) background, used on the sign-in and signature screens.
struct DarkField: View {
    let label: String
    @Binding var text: String
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.fig(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.heroMuted)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .font(.fig(17, .semibold))
            .foregroundStyle(.white)
            .tint(Theme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.forest2, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

extension Date {
    /// "Sat, Oct 3 at 10:00 AM"
    var dayAndTime: String {
        "\(formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(formatted(date: .omitted, time: .shortened))"
    }
}
