import SwiftUI
import UIKit

struct CodeScreen: View {
    @ObservedObject var model: AppModel
    let apply: (Recipe) -> Void
    let close: () -> Void
    let premium: () -> Void

    @State private var input = ""
    @State private var checkedInput: String?
    @FocusState private var keyboard: Bool
    private var recipe: Recipe? { Recipe.parse(input) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("code.title")) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closeCode", action: close)
            }
            PageScroll {
                VStack(alignment: .leading, spacing: 9) {
                    Text(L.t("code.field")).font(.headline)
                    HStack {
                        TextField("PT1:softpink:60", text: $input)
                            .font(.system(.subheadline, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .submitLabel(.go)
                            .focused($keyboard)
                            .onSubmit(finish)
                            .onChange(of: input) { _, value in
                                if value.utf8.prefix(66).count > 65 { input = Recipe.parse(value)?.code ?? String(value.prefix(65)) }
                            }
                            .padding(10).frame(minHeight: 44)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line) }
                            .accessibilityLabel(L.t("code.field"))
                            .accessibilityIdentifier("presetCode")
                        if keyboard {
                            HeaderButton(icon: "keyboard.chevron.compact.down", title: L.t("nav.keyboard"),
                                         id: "dismissCodeKeyboard") { keyboard = false }
                        }
                    }
                    ToneButton(title: L.t("code.paste"), icon: "document.on.clipboard", id: "pasteCode", kind: .soft) {
                        keyboard = false
                        let value = UIPasteboard.general.string ?? ""
                        input = Recipe.parse(value)?.code ?? String(value.prefix(65))
                        checkedInput = input
                    }
                }.padding(14).toneCard()
                if let recipe {
                    preview(recipe)
                } else if checkedInput == input {
                    ErrorNote(text: L.t("code.invalid"))
                }
                Label(L.t("code.privacy"), systemImage: "checkmark.shield").toneNote()
            }
            BottomActions {
                let locked = recipe.map { !model.access.allows($0.preset) } ?? false
                ToneButton(title: L.t(locked ? "purchase.details" : "code.use"),
                           icon: locked ? "lock" : "checkmark", id: "applyCode") {
                    if locked { keyboard = false; premium() } else { finish() }
                }
                .disabled(input.isEmpty)
                Text(L.t("code.useNote")).toneNote()
            }
        }
    }

    private func preview(_ recipe: Recipe) -> some View {
        let usable = model.access.allows(recipe.preset)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L.t("code.preview")).font(.headline)
                Spacer()
                StatusPill(title: L.t(usable ? "code.available" : "purchase.premium"),
                           color: usable ? Theme.sage : Theme.apricot,
                           icon: usable ? "checkmark" : "lock")
            }
            HStack(spacing: 12) {
                SampleImage(model: model, name: "cafe", recipe: recipe, maxSide: 260)
                    .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.preset.name).font(.headline)
                    Text(L.f("code.intensity", recipe.strength)).toneNote()
                }
                Spacer()
            }
        }.padding(14).toneCard()
            .accessibilityElement(children: .contain).accessibilityIdentifier("codePreview")
    }

    private func finish() {
        keyboard = false
        checkedInput = input
        guard let recipe, model.access.allows(recipe.preset) else { return }
        apply(recipe)
    }
}

struct SavedPresetsScreen: View {
    @ObservedObject var model: AppModel
    let apply: (Recipe) -> Void
    let close: () -> Void
    let premium: () -> Void
    @State private var copied: UUID?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("saved.title")) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closePresets", action: close)
            }
            PageScroll {
                if model.draft.savedPresets.isEmpty {
                    VStack(spacing: 10) {
                        EmptyIllustration()
                        Text(L.t("saved.empty")).toneNote().multilineTextAlignment(.center)
                        ToneButton(title: L.t("nav.back"), icon: "chevron.left", id: "emptyBack", kind: .soft, action: close)
                    }.padding(16).toneCard()
                }
                ForEach(model.draft.savedPresets) { item in
                    HStack(spacing: 6) {
                        IconRow(title: item.name, subtitle: "\(item.recipe.preset.name) · \(item.recipe.strength)%",
                                symbol: "bookmark", color: Theme.apricot, id: "saved.\(item.id)") {
                            if model.access.canSavePreset { apply(item.recipe) } else { premium() }
                        }
                        if model.access.canSavePreset {
                            HeaderButton(icon: copied == item.id ? "checkmark" : "document.on.document",
                                         title: L.t("share.copy"), id: "copy.\(item.id)") {
                                UIPasteboard.general.string = item.recipe.code
                                copied = item.id
                            }.padding(.trailing, 10)
                        }
                    }.toneCard()
                }
            }
        }
    }
}

struct SavePresetScreen: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var name = ""
    @State private var overwrite = false
    @State private var invalid = false
    @FocusState private var keyboard: Bool

    private var initial: String { "\(model.draft.recipe.preset.name) \(model.draft.recipe.strength)%" }
    private var resolved: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((value.isEmpty ? initial : value).prefix(32))
    }
    private var exists: Bool { model.draft.savedPresets.contains { $0.name == resolved } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("saved.saveAction")) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closeSavePreset", action: close)
            }
            PageScroll {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("saved.name")).font(.headline)
                    HStack {
                        TextField(initial, text: $name)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { keyboard = false }
                            .focused($keyboard)
                            .padding(10).frame(minHeight: 44)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityLabel(L.t("saved.name"))
                            .accessibilityIdentifier("presetName")
                        if keyboard {
                            HeaderButton(icon: "keyboard.chevron.compact.down", title: L.t("nav.keyboard"),
                                         id: "dismissNameKeyboard") { keyboard = false }
                        }
                    }
                    if exists {
                        Toggle(L.t("saved.overwrite"), isOn: $overwrite).accessibilityIdentifier("overwritePreset")
                    }
                    if invalid { ErrorNote(text: model.problem?.localizedDescription ?? L.t("saved.unavailable")) }
                }.padding(14).toneCard()
            }
            BottomActions {
                ToneButton(title: L.t("saved.confirm"), icon: "bookmark.fill", id: "confirmSavePreset") {
                    keyboard = false
                    if model.savePreset(name: resolved, overwrite: overwrite) { close() } else { invalid = true }
                }.disabled(exists && !overwrite)
            }
        }
    }
}

