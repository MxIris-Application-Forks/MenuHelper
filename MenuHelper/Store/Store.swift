//
//  Store.swift
//  MenuHelper
//
//  Created by Kyle on 2022/2/13.
//

import Foundation
import StoreKit
import SwiftUI

typealias Transaction = StoreKit.Transaction

enum StoreError: Error {
    case failedVerification
}

@MainActor
@Observable
final class Store {
    private(set) var coffies: [Product] = []
    private(set) var purchased = false
    var updateListenerTask: Task<Void, Never>?

    private let storage = NSUbiquitousKeyValueStore.default
    private static let purchasedKey = "PURCHASED"

    private let productIdentifiers = [
        "consumable.coffie.price1",
        "consumable.coffie.price2",
        "consumable.coffie.price3",
    ]

    init() {
        updateListenerTask = listenForTransactions()
        Task {
            await requestProducts()
        }
    }

    isolated deinit {
        updateListenerTask?.cancel()
    }

    func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            // Iterate through any transactions which didn't come from a direct call to `purchase()`.
            for await verificationResult in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(verificationResult)
                    // Deliver content to the user.
                    self.updatePurchasedIdentifiers(transaction)
                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a receipt it can read but it failed verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }

    func requestProducts() async {
        do {
            let storeProducts = try await Product.products(for: productIdentifiers)
            coffies = storeProducts.filter { $0.type == .consumable }.sorted(by: \.price)
        } catch {
            print("Failed product request: \(error)")
        }
    }

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            // Deliver content to the user.
            updatePurchasedIdentifiers(transaction)
            // Always finish a transaction.
            await transaction.finish()
            return transaction
        case .userCancelled, .pending:
            return nil
        default:
            return nil
        }
    }

    private func checkVerified<VerifiedValue>(
        _ verificationResult: VerificationResult<VerifiedValue>
    ) throws -> VerifiedValue {
        // Check if the transaction passes StoreKit verification.
        switch verificationResult {
        case .unverified:
            // StoreKit has parsed the JWS but failed verification. Don't deliver content to the user.
            throw StoreError.failedVerification
        case let .verified(verifiedValue):
            // If the transaction is verified, unwrap and return it.
            return verifiedValue
        }
    }

    private func updatePurchasedIdentifiers(_ transaction: Transaction) {
        if transaction.revocationDate == nil {
            // If the App Store has not revoked the transaction, add it to the list of `purchasedIdentifiers`.
            storage.set(true, forKey: Store.purchasedKey)
            purchased = true
        } else {
            // If the App Store has revoked this transaction, remove it from the list of `purchasedIdentifiers`.
            storage.set(false, forKey: Store.purchasedKey)
            purchased = false
        }
    }

    func refreshPurchased() {
        purchased = storage.bool(forKey: Store.purchasedKey)
    }
}

extension Sequence {
    func sorted<ComparableValue: Comparable>(
        by keyPath: KeyPath<Element, ComparableValue>
    ) -> [Element] {
        sorted { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }
}
