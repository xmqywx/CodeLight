import Foundation
import StoreKit
import CodeLightCrypto

/// Manages StoreKit 2 in-app purchases for the CodeLight lifetime unlock.
///
/// Key design decisions:
/// - `isPurchased` tracks LOCAL StoreKit entitlement only. Server enforces its own gate.
/// - Transaction listener lives forever (never cancelled). Events arriving in background
///   are handled on next wake.
/// - `verifyWithServer` is self-contained (own URLRequest), decoupled from SocketClient.
/// - Pending verify survives app kill via UserDefaults, retried on every socket reconnect.
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let productID = "com.codelight.app.lifetime"

    @Published var product: Product?
    @Published var isPurchased: Bool = false
    @Published var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case verifying
        case success
        case error(String)
    }

    private var transactionListener: Task<Void, Never>?
    private let pendingVerifyKey = "pendingOriginalTransactionId"

    private init() {}

    // MARK: - Lifecycle

    /// Call once from CodeLightApp.task. Loads product, checks entitlement,
    /// starts the transaction listener that lives until process death.
    func start() {
        Task {
            await loadProduct()
            await checkEntitlement()
            listenForTransactions()
        }
    }

    // MARK: - Product Loading

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            print("[StoreManager] Failed to load products: \(error)")
        }
    }

    // MARK: - Entitlement Check

    /// Check local StoreKit entitlement. Does NOT hit the server.
    func checkEntitlement() async {
        guard let result = await Transaction.currentEntitlement(for: Self.productID) else {
            isPurchased = false
            return
        }
        switch result {
        case .verified(let tx):
            if tx.revocationDate != nil {
                isPurchased = false
            } else {
                isPurchased = true
            }
        case .unverified:
            isPurchased = false
        }
    }

    // MARK: - Purchase

    /// Purchase the lifetime product. Returns the verified transaction on success.
    @discardableResult
    func purchase() async throws -> Transaction? {
        guard let product else {
            purchaseState = .error(String(localized: "store_product_unavailable"))
            return nil
        }

        purchaseState = .purchasing

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            purchaseState = .error(error.localizedDescription)
            return nil
        }

        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let tx):
                isPurchased = true
                purchaseState = .verifying

                // Persist for retry in case server is unreachable
                savePendingVerify(originalTransactionId: tx.originalID)
                await verifyWithServer(originalTransactionId: tx.originalID)

                await tx.finish()
                purchaseState = .success
                return tx

            case .unverified(_, let error):
                purchaseState = .error(String(localized: "store_verification_failed"))
                print("[StoreManager] Unverified transaction: \(error)")
                return nil
            }

        case .pending:
            // Ask to Buy or other deferred flow
            purchaseState = .idle
            return nil

        case .userCancelled:
            purchaseState = .idle
            return nil

        @unknown default:
            purchaseState = .idle
            return nil
        }
    }

    // MARK: - Restore

    /// Restore purchases (triggers App Store sync + re-checks entitlement).
    func restorePurchase() async throws {
        try await AppStore.sync()
        await checkEntitlement()

        // If restored, also verify with server
        if isPurchased {
            if let result = await Transaction.currentEntitlement(for: Self.productID),
               case .verified(let tx) = result {
                savePendingVerify(originalTransactionId: tx.originalID)
                await verifyWithServer(originalTransactionId: tx.originalID)
            }
        }
    }

    // MARK: - Transaction Listener

    /// Listens for transaction updates for the entire app lifetime.
    /// Catches: Ask-to-Buy completions, Family Sharing grants, refunds.
    private func listenForTransactions() {
        guard transactionListener == nil else { return }

        transactionListener = Task { @MainActor [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                switch result {
                case .verified(let tx):
                    if tx.revocationDate != nil {
                        // Refund: revoke access
                        self.isPurchased = false
                    } else {
                        self.isPurchased = true
                        self.savePendingVerify(originalTransactionId: tx.originalID)
                        await self.verifyWithServer(originalTransactionId: tx.originalID)
                    }
                    await tx.finish()
                case .unverified:
                    break
                }
            }
        }
    }

    // MARK: - Server Verification

    /// Notify the server of a successful purchase. Self-contained: builds its own
    /// URLRequest with the current server URL + auth token. Does NOT depend on
    /// AppState.socket (which can be nil during reconnect).
    ///
    /// `originalTransactionId` is UInt64 from StoreKit 2, sent as String because
    /// UInt64 exceeds JavaScript's Number.MAX_SAFE_INTEGER (2^53-1).
    private func verifyWithServer(originalTransactionId: UInt64) async {
        guard let serverUrl = AppState.shared.currentServerUrl ?? AppState.shared.lastUsedServerUrl else {
            print("[StoreManager] No server URL available for verify")
            return
        }

        let keyManager = KeyManager(serviceName: "com.codelight.app")
        guard let token = keyManager.loadToken(forServer: serverUrl) else {
            print("[StoreManager] No auth token for \(serverUrl)")
            return
        }

        let url = URL(string: "\(serverUrl)/v1/subscription/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = ["originalTransactionId": "\(originalTransactionId)"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success {
                    clearPendingVerify()
                    print("[StoreManager] Server verify success")
                    return
                }
            }
            print("[StoreManager] Server verify failed, will retry on next connect")
        } catch {
            print("[StoreManager] Server verify network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Pending Verify Persistence

    private func savePendingVerify(originalTransactionId: UInt64) {
        UserDefaults.standard.set("\(originalTransactionId)", forKey: pendingVerifyKey)
    }

    private func clearPendingVerify() {
        UserDefaults.standard.removeObject(forKey: pendingVerifyKey)
    }

    /// Called from AppState on every successful socket reconnect.
    /// If a pending verify exists, retries the server call.
    func retryPendingVerify() async {
        guard let idString = UserDefaults.standard.string(forKey: pendingVerifyKey),
              let id = UInt64(idString) else { return }
        print("[StoreManager] Retrying pending verify for \(idString)")
        await verifyWithServer(originalTransactionId: id)
    }
}
