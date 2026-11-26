import SwiftUI

struct HomeScreen: View {
    @ObservedObject var model: AppModel
    let pick: () -> Void
    let open: (Screen) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("home.title")) {
                HeaderButton(icon: "gearshape", title: L.t("settings.title"), id: "openSettings") { open(.settings) }
            }
            PageScroll {
                hero
                if !model.draft.photos.isEmpty && !model.importing {
                    IconRow(title: model.hasUnfinishedJob ? L.t("home.resume") : L.t("home.draft"),
                            subtitle: L.f("photo.count", model.draft.photos.count),
                            symbol: "photo.stack", color: Theme.rose, id: "resumeDraft") {
                        open(model.hasUnfinishedJob ? .status : .editor)
                    }.toneCard()
                }
                Text(L.t("preset.title")).font(.headline)
                HStack(alignment: .top, spacing: 11) {
                    IconTile(title: L.t("saved.title"), subtitle: L.t("home.savedNote"), symbol: "bookmark",
                             color: Theme.apricot, id: "myPresets") { open(.presets) }
                    IconTile(title: L.t("code.title"), subtitle: L.t("home.importNote"), symbol: "document.badge.arrow.up",
                             color: Theme.sage, id: "importPreset") { open(.code) }
                }
                Label(L.t("home.local"), systemImage: "checkmark.shield")
                    .toneNote()
                if let problem = model.problem { ErrorNote(text: problem.localizedDescription) }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 11) {
            GeometryReader { geometry in
                let w = min(geometry.size.width, 355)
                ZStack {
                    print(name: "cafe", width: w * 0.48, height: 142)
                        .rotationEffect(.degrees(-11)).offset(x: -w * 0.19, y: 8)
                    print(name: "portrait", width: w * 0.49, height: 177)
                        .rotationEffect(.degrees(8)).offset(x: w * 0.10, y: 0)
                    SmallIcon(name: "photo.on.rectangle").rotationEffect(.degrees(-8))
                        .offset(x: -w * 0.41, y: -75)
                    SmallIcon(name: "sparkles", color: Theme.apricot).scaleEffect(0.76)
                        .offset(x: -w * 0.32, y: 84)
                    SmallIcon(name: "slider.horizontal.3", color: Theme.sage).rotationEffect(.degrees(10))
                        .offset(x: w * 0.41, y: 70)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 208)
            .accessibilityHidden(true)
            Text(L.t("home.hero")).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text(L.t("home.subtitle")).toneNote()
            ToneButton(title: L.t("home.pick"), icon: "photo.on.rectangle", id: "pickPhotos", action: pick)
                .disabled(!model.canOpenPhotos)
            if model.importing { ProgressView(L.t("photo.loading")) }
            if !model.access.pro {
                Text(L.t("home.freeLimit")).toneNote()
            }
        }
        .padding(17)
        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.line) }
        .toneCard(fill: Theme.background)
    }

    private func print(name: String, width: CGFloat, height: CGFloat) -> some View {
        SampleImage(model: model, name: name, recipe: Recipe())
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(6).padding(.bottom, 8)
            .background(.white, in: RoundedRectangle(cornerRadius: 9))
            .shadow(color: Theme.ink.opacity(0.16), radius: 7, x: 1, y: 6)
    }
}

