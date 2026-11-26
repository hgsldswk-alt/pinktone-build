import SwiftUI
import StoreKit

struct SettingsScreen: View {
    @ObservedObject var model: AppModel
    let open: (Screen) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("settings.title")) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closeSettings", action: close)
            }
            PageScroll {
                premiumCard(model: model) {
                    ToneButton(title: L.t("purchase.details"), icon: "checkmark.seal",
                               id: "openPaywall", kind: .outline) { open(.paywall) }
                }
                Text(L.t("settings.collection")).font(.headline)
                VStack(spacing: 0) {
                    IconRow(title: L.t("saved.title"), subtitle: L.t("settings.savedNote"), symbol: "bookmark",
                            color: Theme.apricot, id: "settingsPresets") { open(.presets) }
                    Divider()
                    IconRow(title: L.t("code.title"), subtitle: L.t("settings.codeNote"),
                            symbol: "document.on.clipboard", color: Theme.sage, id: "settingsImport") { open(.code) }
                    Divider()
                    IconRow(title: L.t("milestone.title"),
                            subtitle: model.draft.activity.totalSaved >= 100
                                ? L.t("milestone.reached") : L.f("milestone.progress", model.draft.activity.totalSaved),
                            symbol: "rosette", color: Theme.rose, id: "openMilestone") { open(.milestone) }
                }.toneCard()
                Text(L.t("settings.support")).font(.headline)
                VStack(spacing: 0) {
                    RestoreRow(model: model, purchases: model.purchases)
                    Divider()
                    IconRow(title: L.t("settings.help"), subtitle: L.t("settings.helpNote"), symbol: "checkmark.shield",
                            color: Theme.sage, id: "openHelp") { open(.help) }
                }.toneCard()
            }
        }
    }
}

@MainActor
private func premiumCard<Content: View>(model: AppModel, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .top) {
            Text(L.t("purchase.premium")).font(.headline)
            Spacer()
            let title = model.entitlement.purchasedPro ? L.t("purchase.active")
                : (model.access.pro ? L.f("purchase.trialDays", model.entitlement.remainingDays(at: model.now))
                   : L.t("purchase.free"))
            StatusPill(title: title, color: model.entitlement.purchasedPro ? Theme.sage : Theme.apricot)
        }
        Text(L.t("purchase.features")).toneNote()
        content()
        Text(L.t("purchase.trialNote")).toneNote()
    }
    .padding(14)
    .background(Theme.rose.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.radius))
    .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.line) }
}

struct PaywallScreen: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: Purchases
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("purchase.details")) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closePaywall", action: close)
            }
            PageScroll {
                premiumCard(model: model) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(L.t("purchase.noSubscription")).font(.subheadline.weight(.semibold))
                        Text(L.t("purchase.freeDetails")).toneNote()
                    }
                }
                RestoreRow(model: model, purchases: purchases).toneCard()
            }
            BottomActions {
                ToneButton(title: purchases.product.map { L.f("purchase.buyPrice", $0.displayPrice) }
                           ?? L.t("purchase.buy"), icon: "checkmark.seal", id: "buyPro") {
                    Task { await purchases.buy(accept: model.accept) }
                }.disabled(purchases.busy || model.entitlement.purchasedPro)
            }
        }
        .task { await purchases.loadProduct() }
    }
}

private struct RestoreRow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var purchases: Purchases
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IconRow(title: L.t("purchase.restore"), subtitle: L.t("purchase.restoreNote"),
                    symbol: "arrow.counterclockwise", color: Theme.apricot, id: "restorePurchase") {
                Task { await purchases.restore(accept: model.accept) }
            }.disabled(purchases.busy)
            if purchases.busy { ProgressView().padding(10) }
            if let notice = purchases.notice { Text(notice).toneNote().padding(12) }
            if let problem = purchases.problem { ErrorNote(text: problem).padding(10) }
        }
    }
}

struct HelpScreen: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L.t("settings.help")) {
                HeaderButton(icon: "xmark", title: L.t("nav.close"), id: "closeHelp", action: close)
            }
            PageScroll {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L.t("home.local"), systemImage: "checkmark.shield").font(.headline)
                    Text(L.t("help.privacy")).toneNote()
                    Label(L.t("save.title"), systemImage: "photo.badge.checkmark").font(.headline)
                    Text(L.t("help.save")).toneNote()
                    Text(L.t("edit.sdr")).toneNote()
                }.padding(15).toneCard()
            }
        }
    }
}

