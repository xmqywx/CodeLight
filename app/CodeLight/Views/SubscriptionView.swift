import SwiftUI
import StoreKit

/// Paywall / trial-expiry screen. Three entry points:
/// - `.trialExpired` — automatic, trial ended
/// - `.sessionBlocked` — server sent `subscription-required`
/// - `.voluntary` — user tapped "Upgrade" in Settings
///
/// Always dismissible (swipe or button). Closing without purchase
/// leaves the app in a degraded state — server refuses socket connections
/// until the user subscribes.
struct SubscriptionView: View {
    let reason: AppState.SubscriptionReason

    @EnvironmentObject var appState: AppState
    @ObservedObject var storeManager = StoreManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isRestoring = false
    @State private var restoreError: String?

    private var headline: String {
        switch reason {
        case .trialExpired:
            return String(localized: "sub_trial_ended_title")
        case .sessionBlocked:
            return String(localized: "sub_subscription_required_title")
        case .voluntary:
            return String(localized: "sub_unlock_title")
        }
    }

    private var subtitle: String {
        switch reason {
        case .trialExpired:
            return String(localized: "sub_trial_ended_subtitle")
        case .sessionBlocked:
            return String(localized: "sub_subscription_required_subtitle")
        case .voluntary:
            return String(localized: "sub_unlock_subtitle")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 20)

                        // Already purchased — show success state
                        if storeManager.isPurchased && storeManager.purchaseState != .success {
                            alreadyPurchasedView
                        } else {
                            // App icon
                            appIcon

                            // Headline + subtitle
                            VStack(spacing: 8) {
                                Text(headline)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.center)

                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal, 32)

                            // Feature list
                            featureList

                            // Price
                            priceDisplay

                            // Purchase button
                            purchaseButton

                            // Restore
                            restoreButton

                            // Error messages
                            errorArea

                            // Footer
                            footerLinks
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .interactiveDismissDisabled(storeManager.purchaseState == .purchasing)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Already Purchased

    private var alreadyPurchasedView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.brand)

            Text(String(localized: "sub_already_purchased_title"))
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Theme.textPrimary)

            Text(String(localized: "sub_already_purchased_subtitle"))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                dismiss()
            } label: {
                Text(String(localized: "done"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.onBrand)
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - App Icon

    private var appIcon: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 48))
            .foregroundStyle(Theme.brand)
            .frame(width: 80, height: 80)
            .background(Theme.bgElevated, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow("checkmark.circle.fill", String(localized: "sub_feature_sessions"))
            featureRow("checkmark.circle.fill", String(localized: "sub_feature_multi_mac"))
            featureRow("checkmark.circle.fill", String(localized: "sub_feature_sync"))
            featureRow("checkmark.circle.fill", String(localized: "sub_feature_island"))
            featureRow("star.circle.fill", String(localized: "sub_feature_lifetime"), highlight: true)
        }
        .padding(20)
        .brandSurface(corner: 12)
        .padding(.horizontal, 32)
    }

    private func featureRow(_ icon: String, _ text: String, highlight: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brand)
                .font(.system(size: 18))
            Text(text)
                .font(highlight ? .body.bold() : .body)
                .foregroundStyle(highlight ? Theme.brand : Theme.textPrimary)
        }
    }

    // MARK: - Price

    private var priceDisplay: some View {
        VStack(spacing: 4) {
            if let product = storeManager.product {
                Text(product.displayPrice)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.brand)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(String(localized: "sub_one_time_forever"))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task { await handlePurchase() }
        } label: {
            Group {
                switch storeManager.purchaseState {
                case .purchasing, .verifying:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.onBrand)
                        Text(storeManager.purchaseState == .verifying
                             ? String(localized: "sub_verifying")
                             : String(localized: "sub_purchasing"))
                            .font(.headline)
                    }
                case .success:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(String(localized: "sub_success"))
                            .font(.headline)
                    }
                default:
                    Text(String(localized: "sub_unlock_button"))
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                storeManager.purchaseState == .success ? Theme.success : Theme.brand,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(Theme.onBrand)
        }
        .padding(.horizontal, 40)
        .disabled(storeManager.product == nil
                  || storeManager.purchaseState == .purchasing
                  || storeManager.purchaseState == .verifying
                  || storeManager.purchaseState == .success)
        .opacity(storeManager.product == nil ? 0.5 : 1)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await handleRestore() }
        } label: {
            if isRestoring {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(String(localized: "sub_restore_purchase"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .disabled(isRestoring)
    }

    // MARK: - Error Area

    @ViewBuilder
    private var errorArea: some View {
        if case .error(let message) = storeManager.purchaseState {
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }

        if let restoreError {
            Text(restoreError)
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Footer

    private var footerLinks: some View {
        HStack(spacing: 16) {
            Link(String(localized: "privacy_policy"),
                 destination: URL(string: "https://github.com/MioMioOS/CodeLight/blob/main/PRIVACY.md")!)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)

            Text("·")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)

            Link(String(localized: "sub_terms"),
                 destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Actions

    private func handlePurchase() async {
        Haptics.medium()
        do {
            let tx = try await storeManager.purchase()
            if tx != nil {
                Haptics.success()
                // Brief pause to show success state
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                appState.isSubscriptionBlocked = false
                dismiss()
            }
        } catch {
            Haptics.error()
        }
    }

    private func handleRestore() async {
        Haptics.medium()
        isRestoring = true
        restoreError = nil
        do {
            try await storeManager.restorePurchase()
            if storeManager.isPurchased {
                Haptics.success()
                appState.isSubscriptionBlocked = false
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            } else {
                restoreError = String(localized: "sub_restore_no_purchase")
                Haptics.error()
            }
        } catch {
            restoreError = error.localizedDescription
            Haptics.error()
        }
        isRestoring = false
    }
}
