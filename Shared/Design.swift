import SwiftUI
import UIKit

enum Theme {
    static let rose = Color(red: 199 / 255.0, green: 125 / 255.0, blue: 134 / 255.0)
    static let apricot = Color(red: 242 / 255.0, green: 201 / 255.0, blue: 160 / 255.0)
    static let sage = Color(red: 127 / 255.0, green: 168 / 255.0, blue: 154 / 255.0)
    static let background = Color(red: 251 / 255.0, green: 246 / 255.0, blue: 244 / 255.0)
    static let ink = Color(red: 46 / 255.0, green: 42 / 255.0, blue: 43 / 255.0)
    static let roseText = Color(red: 130 / 255.0, green: 63 / 255.0, blue: 75 / 255.0)
    static let sageText = Color(red: 54 / 255.0, green: 93 / 255.0, blue: 80 / 255.0)
    static let apricotText = Color(red: 117 / 255.0, green: 76 / 255.0, blue: 46 / 255.0)
    static let muted = Color(red: 102 / 255.0, green: 92 / 255.0, blue: 95 / 255.0)
    static let line = Color(red: 235 / 255.0, green: 219 / 255.0, blue: 217 / 255.0)
    static let gradient = LinearGradient(colors: [rose.opacity(0.29), apricot.opacity(0.23)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let cardBorder = LinearGradient(colors: [rose, apricot], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let radius: CGFloat = 18

    static func textColor(on color: Color) -> Color {
        if color == sage { return sageText }
        if color == apricot { return apricotText }
        return roseText
    }
}

extension View {
    func toneCard(fill: Color = .white) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: Theme.radius))
            .shadow(color: Theme.ink.opacity(0.075), radius: 9, x: 0, y: 4)
    }

    func toneNote() -> some View {
        font(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
    }
}

struct ToneButtonStyle: ButtonStyle {
    enum Kind { case primary, soft, outline }
    let kind: Kind
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .primary ? .system(size: 19, weight: .bold) : .subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(kind == .primary && enabled ? .white : Theme.roseText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: kind == .primary ? 52 : 44)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                if kind == .outline {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var fill: Color {
        if !enabled { return Theme.rose.opacity(0.20) }
        switch kind {
        case .primary: return Theme.rose
        case .soft: return Theme.rose.opacity(0.15)
        case .outline: return .white
        }
    }
}

struct ToneButton: View {
    let title: String
    let icon: String
    let id: String
    var kind: ToneButtonStyle.Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .buttonStyle(ToneButtonStyle(kind: kind))
            .accessibilityIdentifier(id)
    }
}

struct SmallIcon: View {
    let name: String
    var color: Color = Theme.rose
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.textColor(on: color))
            .frame(width: 38, height: 38)
            .background(color.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let title: String
    var color: Color = Theme.rose
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(title).lineLimit(2)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.textColor(on: color))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.20), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct HeaderButton: View {
    let icon: String
    let title: String
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.roseText)
                .frame(width: 44, height: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.line) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font((subtitle == nil ? Font.title : Font.title2).weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).toneNote() }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct IconTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                SmallIcon(name: symbol, color: color)
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).toneNote()
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .padding(12)
            .toneCard()
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct IconRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SmallIcon(name: symbol, color: color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).toneNote()
                }
                Spacer(minLength: 5)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(Theme.roseText).accessibilityHidden(true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct EmptyIllustration: View {
    var body: some View {
        ZStack {
            SmallIcon(name: "photo.on.rectangle").rotationEffect(.degrees(-12)).offset(x: -23, y: -10)
            SmallIcon(name: "slider.horizontal.3", color: Theme.sage).rotationEffect(.degrees(12)).offset(x: 23, y: 1)
            SmallIcon(name: "sparkles", color: Theme.apricot).scaleEffect(0.75).offset(y: 22)
        }
        .frame(width: 110, height: 82)
        .accessibilityHidden(true)
    }
}

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 20)
                .padding(.top, 5)
                .padding(.bottom, 18)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct BottomActions<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
    }
}

struct ErrorNote: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(Theme.roseText)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.apricot.opacity(0.26), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("problem")
    }
}

struct SampleImage: View {
    @ObservedObject var model: AppModel
    let name: String
    let recipe: Recipe
    var maxSide: Int = 720
    @State private var rendered: CGImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let rendered { Image(decorative: rendered, scale: 1).resizable().scaledToFill() }
                else { Theme.apricot.opacity(0.22) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: recipe) {
            guard let source = UIImage(named: name)?.cgImage,
                  let output = try? await model.previews.demo(source, recipe: recipe, maxSide: maxSide),
                  !Task.isCancelled else { return }
            rendered = output.edited
        }
        .accessibilityHidden(true)
    }
}

