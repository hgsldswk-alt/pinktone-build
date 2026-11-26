import Combine
import PhotosUI
import StoreKit
import SwiftUI
import UIKit

@main
@MainActor
struct PinkToneApp: App {
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.light) }
    }
}

enum Screen: Equatable {
    case home, editor, status, share, code, settings, presets, savePreset, milestone, paywall, help
}

private enum PickMode {
    case new, add, replace(PhotoItem)
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scene
    @Environment(\.requestReview) private var requestReview
    @State private var stack: [Screen] = Launch.arguments.contains("-paywall")
        ? [.home, .settings, .paywall] : [.home]
    @State private var showPicker = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var pickerMode: PickMode = .new
    @State private var showDiscard = false
    @State private var focusedID: UUID?
    @State private var grid = false
    @State private var compare: CompareInput?
    @State private var pickerLimit = 0
    @State private var starting = false

    private var screen: Screen { stack.last ?? .home }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            screenBody
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.rose)
        .photosPicker(isPresented: $showPicker, selection: $picked, maxSelectionCount: pickerLimit,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: picked) { _, selection in
            guard !selection.isEmpty else { return }
            let mode = pickerMode
            picked = []
            Task {
                switch mode {
                case .replace(let item):
                    if let photo = selection.first { await model.replace(item, with: photo) }
                case .new, .add:
                    await openPhotos(mode: mode, selection: selection)
                }
            }
        }
        .onChange(of: scene) { _, current in
            if current == .background { model.stop() }
            if current == .active { model.refreshClock() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.stop()
        }
        .task { await model.purchases.start(accept: model.accept) }
        .task {
            model.refreshClock()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if scene == .active { model.refreshClock() }
            }
        }
        .task(id: screen == .home && scene == .active && !showPicker && !showDiscard && !starting) {
            guard screen == .home, scene == .active, !showPicker, !showDiscard, !starting else { return }
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            model.askForReviewIfReady(version: version) { requestReview() }
        }
        .accessibilityHidden(showDiscard)
        .overlay {
            if showDiscard { discardPanel }
        }
    }

    @ViewBuilder private var screenBody: some View {
        switch screen {
        case .home:
            HomeScreen(model: model, pick: { choose(.new) }, open: open)
        case .editor:
            EditorScreen(model: model, focusedID: $focusedID, grid: $grid, close: home,
                         add: { choose(.add) }, replace: { choose(.replace($0)) }, open: open,
                         share: openShare, save: {
                guard !starting else { return }
                starting = true
                open(.status)
                Task {
                    await model.startSave()
                    starting = false
                }
            })
        case .status:
            StatusScreen(model: model, starting: starting, preferredPhoto: focusedID,
                         edit: { go(.editor) }, home: home, open: open,
                         share: openShare, replace: { choose(.replace($0)) })
        case .share:
            ShareScreen(model: model, compare: compare, close: back)
        case .milestone:
            ShareScreen(model: model, compare: nil, close: back)
        case .code:
            CodeScreen(model: model, apply: apply, close: back, premium: { open(.paywall) })
        case .presets:
            SavedPresetsScreen(model: model, apply: apply, close: back, premium: { open(.paywall) })
        case .savePreset:
            SavePresetScreen(model: model, close: back)
        case .settings:
            SettingsScreen(model: model, open: open, close: back)
        case .paywall:
            PaywallScreen(model: model, purchases: model.purchases, close: back)
        case .help:
            HelpScreen(close: back)
        }
    }

    private func open(_ next: Screen) {
        guard screen != next else { return }
        if next == .editor { grid = model.draft.photos.count > 1 }
        stack.append(next)
    }

    private func back() {
        if stack.count > 1 { stack.removeLast() }
        if screen != .share { compare = nil }
    }

    private func home() {
        model.persistEditor()
        model.closeCompletedSession()
        stack = [.home]
        compare = nil
    }

    private func go(_ next: Screen) {
        stack = [.home, next]
        compare = nil
    }

    private func openShare(item: PhotoItem, recipe: Recipe, watermark: Bool) {
        guard let url = model.source(for: item) else { return }
        compare = CompareInput(url: url, recipe: recipe, watermark: watermark)
        open(.share)
    }

    private func apply(_ recipe: Recipe) {
        guard model.updateRecipe(recipe) else { return }
        model.persistEditor()
        if let editor = stack.firstIndex(of: .editor) {
            stack = Array(stack[...editor])
        } else {
            home()
        }
    }

    private func choose(_ mode: PickMode) {
        guard model.canOpenPhotos, !showPicker else { return }
        pickerMode = mode
        if model.hasUnfinishedJob {
            if case .replace = mode { showSelection(mode) }
            else { showDiscard = true }
        } else {
            showSelection(mode)
        }
    }

    private func showSelection(_ mode: PickMode) {
        #if DEBUG
        if Launch.arguments.contains("-seed") {
            switch mode {
            case .new, .add:
                Task { await openPhotos(mode: mode, selection: []) }
                return
            case .replace: break
            }
        }
        #endif
        switch mode {
        case .replace: pickerLimit = 1
        case .new: pickerLimit = model.access.pickerLimit
        case .add: pickerLimit = model.access.pro ? 0 : max(1, model.access.pickerLimit - model.draft.photos.count)
        }
        picked = []
        showPicker = true
    }

    private func openPhotos(mode: PickMode, selection: [PhotosPickerItem]) async {
        let appending: Bool
        switch mode {
        case .add: appending = true
        default: appending = false
        }
        let imported: Bool
        #if DEBUG
        if Launch.arguments.contains("-seed") {
            let count = Launch.arguments.contains("-single") ? 1 : (Launch.arguments.contains("-three") ? 3 : 6)
            imported = await model.seed(appending: appending, count: count)
        } else {
            imported = await model.select(selection, appending: appending)
        }
        #else
        imported = await model.select(selection, appending: appending)
        #endif
        if imported {
            focusedID = nil
            grid = model.draft.photos.count > 1
            go(.editor)
        }
    }

    private var discardPanel: some View {
        ZStack {
            Theme.ink.opacity(0.32).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("save.discardTitle")).font(.headline)
                Text(L.t("save.discardNote")).toneNote()
                ToneButton(title: L.t("save.discard"), icon: "arrow.right", id: "confirmDiscard") {
                    let mode = pickerMode
                    showDiscard = false
                    showSelection(mode)
                }
                ToneButton(title: L.t("nav.cancel"), icon: "xmark", id: "cancelDiscard", kind: .outline) {
                    showDiscard = false
                }
            }.padding(18).toneCard().padding(26).frame(maxWidth: 440)
        }
        .accessibilityElement(children: .contain)
    }
}

