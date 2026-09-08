import Foundation
import ManagedSettings

/// Makes the ManagedSettings shields match the persisted rules. Idempotent; call it from anywhere, anytime.
enum ShieldReconciler {
    static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(Furlough.storeName))
    }

    @discardableResult
    /// `now` is Furlough's own time; it defaults to reading it, so no caller can hand the
    /// shields a device clock that was moved forward.
    static func reconcile(now: Date? = nil, reason: String) -> Decision {
        var state = SharedStore.load()
        let now = now ?? state.now
        if Policy.applyDuePending(&state, now: now) {
            SharedStore.log("applied due pending changes during reconcile")
        }
        let decision = Policy.decide(config: state.config, runtime: state.runtime, now: now)
        apply(decision)
        state.runtime.lastReconcile = now
        SharedStore.save(state)
        SharedStore.log(
            "reconcile (\(reason)): shielded apps=\(decision.shieldedApps.count) web=\(decision.shieldedWeb.count) "
            + "categories=\(decision.categories.count) open apps=\(decision.allowedApps.count) web=\(decision.allowedWeb.count)"
        )
        return decision
    }

    static func apply(_ decision: Decision) {
        let store = store
        store.shield.applications = decision.shieldedApps.isEmpty ? nil : decision.shieldedApps
        store.shield.applicationCategories = decision.categories.isEmpty
            ? nil
            : .specific(decision.categories, except: decision.allowedApps)
        store.shield.webDomains = decision.shieldedWeb.isEmpty ? nil : decision.shieldedWeb
        store.shield.webDomainCategories = decision.categories.isEmpty
            ? nil
            : .specific(decision.categories, except: decision.allowedWeb)
        // Deny deleting apps only while something is shielded, so the flag can never outlive a block.
        store.application.denyAppRemoval = decision.isAnythingShielded ? true : nil
    }

    /// Removes every setting Furlough ever applied.
    static func clearEverything() {
        store.clearAllSettings()
        SharedStore.log("cleared all managed settings")
    }
}
