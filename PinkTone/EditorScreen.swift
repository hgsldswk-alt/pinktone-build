import SwiftUI

private struct PreviewKey: Hashable {
    let path: URL
    let recipe: Recipe
    let watermark: Bool
}

struct EditorScreen: View {
    @ObservedObject var model: AppModel
    @Binding var focusedID: UUID?
    @Binding var grid: Bool
    let close: () -> Void
    let add: () -> Void
    let replace: (PhotoItem) -> Void
    let open: (Screen) -> Void
    let share: (PhotoItem, Recipe, Bool) -> Void
    let save: () -> Void

    @Environment(\.scenePhase) private var scene
    @Environment(\.displayScale) private var scale
    @GestureState private var pressed = false
    @State private var showsOriginal = false
    @State private var holdCount = 0
    @State private var preview: TonePreview?
    @State private var renderedKey: PreviewKey?
    @State private var badKey: PreviewKey?
    @State private var previewIssue: ToneError?

    private var photos: [PhotoItem] { model.draft.photos }
    private var recipe: Recipe { model.draft.recipe }
    private var focused: PhotoItem? {
        photos.first { $0.id == focusedID } ?? photos.first { $0.file != nil } ?? photos.first
    }
    private var multi: Bool { grid }
    private var isOriginal: Bool { scene == .active && (pressed || showsOriginal) }
    private var key: PreviewKey? {
        guard let focused, let url = model.source(for: focused) else { return nil }
        return PreviewKey(path: url, recipe: recipe, watermark: model.access.watermark)
    }
    private var ready: Bool { key != nil && renderedKey == key && !model.importing }
    private var canRenderBatch: Bool {
        ready || (!model.importing && (key == nil || badKey == key)
                  && photos.contains { $0.id != focused?.id && $0.file != nil })
    }
    private var allowed: Bool { model.access.allows(count: photos.count) && model.access.allows(recipe.preset) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t(multi ? "edit.batch" : "edit.single"),
                       subtitle: selectionSubtitle) {
                if multi {
                    HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closeEditor", action: close)
                } else {
                    HeaderButton(icon: "photo.on.rectangle.angled", title: L.t("edit.batch"), id: "showGrid") {
                        grid = true
                    }
                }
            }
            PageScroll {
                if multi { gridPanel }
                else { focusPanel }
                if model.importing {
                    ProgressView(L.t("photo.loading")).accessibilityIdentifier("photoLoading")
                }
                PresetStrip(model: model, select: select)
                strength
                if !multi { secondary }
                if model.access.watermark { Text(L.t("edit.watermark")).toneNote() }
                if photos.contains(where: \.makesSDR) { Text(L.t("edit.sdr")).toneNote() }
                if !allowed && !model.hasUnfinishedJob { ErrorNote(text: L.t("edit.freeLimit")) }
                if let issue = model.problem { ErrorNote(text: issue.localizedDescription) }
            }
            BottomActions {
                ToneButton(title: saveTitle, icon: "square.and.arrow.down", id: "saveBatch") {
                    if model.hasUnfinishedJob { open(.status) } else { save() }
                }
                .disabled(!(model.hasUnfinishedJob || (canRenderBatch && allowed)))
                Text(L.t("edit.saveNote")).toneNote()
            }
        }
        .task(id: key) {
            guard let key else { return }
            do {
                try await Task.sleep(for: .milliseconds(75))
                let result = try await model.previews.render(key.path, recipe: key.recipe,
                    maxSide: Int(min(1500, 480 * scale)), watermark: key.watermark)
                guard !Task.isCancelled else { return }
                preview = result
                renderedKey = key
                badKey = nil
                previewIssue = nil
            } catch {
                if !Task.isCancelled {
                    badKey = key
                    previewIssue = ToneError.map(error, fallback: .unreadable)
                }
            }
        }
        .onChange(of: focusedID) { _, _ in showsOriginal = false }
        .onChange(of: scene) { _, current in if current != .active { showsOriginal = false } }
        .onChange(of: pressed) { _, current in
            if current && scene == .active { holdCount += 1 }
        }
    }

    private var saveTitle: String {
        if model.hasUnfinishedJob { return L.t("save.title") }
        return photos.count == 1 ? L.t("edit.saveOne") : L.f("edit.saveMany", photos.count)
    }

    private var selectionSubtitle: String {
        if photos.count == 1 { return L.t("edit.selectedOne") }
        return L.f(multi ? "edit.applyCount" : "edit.selectedCount", photos.count)
    }

    private var gridPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("edit.selected")).font(.headline)
                Spacer()
                StatusPill(title: L.f("photo.count", photos.count))
                    .accessibilityIdentifier("selectionCount")
            }
            if photos.count > 4 {
                ScrollView { gridItems }.frame(height: 260)
            } else {
                gridItems
            }
        }
    }

    private var gridItems: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, item in
                Button {
                    focusedID = item.id
                    grid = false
                } label: {
                    PhotoThumbnail(model: model, item: item, recipe: recipe)
                        .frame(height: 127)
                        .overlay(alignment: .topLeading) {
                            StatusPill(title: String(index + 1)).background(.white, in: Capsule()).padding(7)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.f("photo.index", index + 1))
                .accessibilityIdentifier("photo.\(index)")
            }
            if model.access.pro || photos.count < model.access.pickerLimit {
                Button(action: add) {
                    VStack(spacing: 7) {
                        Image(systemName: "plus")
                        Text(L.t("edit.add")).font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.roseText)
                    .frame(maxWidth: .infinity).frame(height: 127)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, style: StrokeStyle(dash: [3])) }
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!model.canOpenPhotos)
                .accessibilityIdentifier("addPhotos")
            }
        }
    }

    @ViewBuilder private var focusPanel: some View {
        if let item = focused {
            if let preview, renderedKey?.path == key?.path, badKey != key {
                picture(preview)
            } else if let issue = item.issue ?? ((badKey != nil && badKey == key) ? previewIssue : nil) {
                VStack(alignment: .leading, spacing: 10) {
                    ErrorNote(text: issue.localizedDescription)
                    if model.canReload(item) {
                        ToneButton(title: L.t("photo.reload"), icon: "arrow.clockwise", id: "reloadPhoto", kind: .soft) {
                            Task { await model.reload(item) }
                        }
                        .disabled(model.importing)
                    }
                    if model.job?.items.first(where: { $0.id == item.id })?.stage != .saved {
                        ToneButton(title: L.t("photo.replace"), icon: "photo", id: "replacePhoto", kind: .outline) {
                            replace(item)
                        }
                        .disabled(model.importing)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .accessibilityIdentifier("previewLoading")
            }
            if photos.count > 1 { filmstrip }
        }
    }

    private func picture(_ preview: TonePreview) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.apricot.opacity(0.24))
            Image(decorative: isOriginal ? preview.original : preview.edited, scale: 1)
                .resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            StatusPill(title: L.t(isOriginal ? "edit.original" : (ready ? "edit.edited" : "edit.updating")))
                .background(.white, in: Capsule())
                .padding(10)
                .accessibilityIdentifier("previewMode")
        }
        .frame(height: 275)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(alignment: .bottom) {
            Text(L.t(pressed ? "edit.release" : "edit.hold"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.roseText)
                .padding(9).frame(minHeight: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .padding(8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t(isOriginal ? "edit.original" : (ready ? "edit.edited" : "edit.updating")))
        .accessibilityValue(String(holdCount))
        .accessibilityIdentifier("holdOriginal")
        .accessibilityAction(named: Text(L.t("edit.toggleOriginal"))) { showsOriginal.toggle() }
        .overlay(alignment: .topTrailing) {
            HeaderButton(icon: "viewfinder", title: L.t("edit.toggleOriginal"), id: "toggleOriginal") {
                showsOriginal.toggle()
            }
            .padding(8)
        }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 7) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, item in
                    Button { focusedID = item.id } label: {
                        PhotoThumbnail(model: model, item: item, recipe: recipe)
                            .frame(width: 48, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                if focused?.id == item.id {
                                    RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rose, lineWidth: 2)
                                }
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.f("photo.index", index + 1))
                    .accessibilityIdentifier("focusPhoto.\(index)")
                }
            }
        }.scrollIndicators(.hidden)
    }

    private var strength: some View {
        VStack(spacing: 4) {
            HStack {
                Text(L.t("edit.strength")).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(recipe.strength)%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.roseText)
                    .accessibilityIdentifier("strengthValue")
            }
            Slider(value: Binding(get: { Double(recipe.strength) }, set: { candidate in
                var next = recipe
                next.strength = Int(candidate.rounded())
                _ = model.updateRecipe(next)
            }), in: 0...100, step: 1, onEditingChanged: { editing in
                if !editing { model.persistEditor() }
            })
            .frame(minHeight: 44)
            .accessibilityLabel(L.t("edit.strength"))
            .accessibilityIdentifier("toneStrength")
            HStack {
                Text("0%")
                Spacer()
                Text("100%")
            }.font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(12).toneCard()
    }

    private var secondary: some View {
        HStack(spacing: 8) {
            ToneButton(title: L.t("saved.saveAction"), icon: "bookmark", id: "savePreset", kind: .outline) {
                open(model.access.canSavePreset ? .savePreset : .paywall)
            }
            ToneButton(title: L.t("share.title"), icon: "rectangle.split.2x1", id: "shareCard", kind: .outline) {
                if let focused { share(focused, recipe, model.access.watermark) }
            }
            .disabled(!ready)
        }
    }

    private func select(_ preset: Preset) {
        var next = recipe
        next.preset = preset
        if model.updateRecipe(next) { model.persistEditor() } else { open(.paywall) }
    }
}

struct PhotoThumbnail: View {
    @ObservedObject var model: AppModel
    let item: PhotoItem
    let recipe: Recipe
    var watermark: Bool? = nil
    @State private var thumbnail: CGImage?
    @State private var missing = false

    private var key: PreviewKey? {
        model.source(for: item).map {
            PreviewKey(path: $0, recipe: recipe, watermark: watermark ?? model.access.watermark)
        }
    }

    var body: some View {
        GeometryReader { layout in
            Group {
                if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() }
                else if missing || item.issue != nil {
                    SmallIcon(name: "exclamationmark.triangle", color: Theme.apricot)
                } else {
                    Theme.apricot.opacity(0.22)
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .clipped()
        }
        .background(Theme.apricot.opacity(0.16))
        .task(id: key) {
            guard let key else { thumbnail = nil; return }
            do {
                try await Task.sleep(for: .milliseconds(125))
                let result = try await model.previews.render(key.path, recipe: key.recipe, maxSide: 300, watermark: key.watermark)
                guard !Task.isCancelled else { return }
                thumbnail = result.edited
                missing = false
            } catch {
                if !Task.isCancelled { thumbnail = nil; missing = true }
            }
        }
        .accessibilityHidden(true)
    }
}

struct PresetStrip: View {
    @ObservedObject var model: AppModel
    let select: (Preset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L.t("preset.title")).font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 7) {
                    ForEach(Preset.allCases) { preset in
                        button(preset)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private func button(_ preset: Preset) -> some View {
        let selected = model.draft.recipe.preset == preset
        let available = model.access.allows(preset)
        return Button { select(preset) } label: {
            VStack(alignment: .leading, spacing: 4) {
                thumbnail(for: preset)
                    .frame(height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topTrailing) {
                        if selected || !available {
                            Image(systemName: available ? "checkmark.circle.fill" : "lock.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.roseText)
                                .background(.white, in: Circle())
                                .padding(3)
                        }
                    }
                Text(preset.name)
                    .font(.caption2.weight(.semibold)).lineLimit(2)
            }
            .padding(4).frame(width: 106, alignment: .topLeading)
            .background(selected ? Theme.rose.opacity(0.16) : .white, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.rose : Theme.line,
                                                                        lineWidth: selected ? 2 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.name)
        .accessibilityValue(available ? "" : L.t("purchase.premium"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("preset.\(preset.rawValue)")
    }

    @ViewBuilder private func thumbnail(for preset: Preset) -> some View {
        let recipe = Recipe(preset: preset, strength: 100)
        if let photo = model.draft.photos.first {
            PhotoThumbnail(model: model, item: photo, recipe: recipe, watermark: false)
                .id(photo.file)
        } else {
            SampleImage(model: model, name: "portrait", recipe: recipe, maxSide: 300)
        }
    }
}

