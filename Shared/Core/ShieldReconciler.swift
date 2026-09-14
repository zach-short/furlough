import Foundation
import ManagedSettings

/// Makes the ManagedSettings shields match the persisted rules. Idempotent; call it from anywhere, anytime.
enum ShieldReconciler {
    static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(Furlough.storeName))
    }

    @discardableResult
    /// `now` is Furlough's own time; defaults to reading it, so no caller can hand the shields
    /// a moved-forward device clock.
    static func reconcile(now: Date? = nil, reason: String) -> Decision {
        var state = SharedStore.load()
        let now = now ?? state.now
        if Policy.applyDuePending(&state, now: now) {
            SharedStore.log("applied due pending changes during reconcile")
        }
        // Makes the stored `isAnchored` flag agree with what `Policy` already reads as released;
        // the monitor's wake at `until` guarantees some process runs this.
        if Policy.liftExpiredAnchor(&state.config, now: now) {
            SharedStore.log("a timed anchor's time had passed; lifted it during reconcile")
        }
        // Pulls what another device wrote, if anything; pure and idempotent.
        if let note = AnchorSync.pull(into: &state.config, now: now) {
            SharedStore.log("iCloud anchor: \(note)")
        }
        // Every callback and every edit ends here, and a status only changes at an edge that
        // wakes us, so this is where the record counts its minutes. See `Record.accumulate`.
        Record.accumulate(&state, now: now)
        let decision = Policy.decide(config: state.config, runtime: state.runtime, now: now)
        apply(decision)
        state.runtime.lastReconcile = now
        SharedStore.save(state)
        SharedStore.log(
            "reconcile (\(reason)): \(decision.shieldsEverything ? "everything shielded; " : "")"
            + "shielded apps=\(decision.shieldedApps.count) web=\(decision.shieldedWeb.count) "
            + "categories=\(decision.categories.count) filtered hosts=\(decision.filteredHosts.count) "
            + "open apps=\(decision.allowedApps.count) web=\(decision.allowedWeb.count) hosts=\(decision.allowedHosts.count)"
        )
        return decision
    }

    static func apply(_ decision: Decision) {
        let store = store
        store.shield.applications = decision.shieldedApps.isEmpty ? nil : decision.shieldedApps
        // Category policy and filter live on `Decision`, next to the sets they're built from.
        store.shield.applicationCategories = decision.appCategoryPolicy
        store.shield.webDomains = decision.shieldedWeb.isEmpty ? nil : decision.shieldedWeb
        store.shield.webDomainCategories = decision.webCategoryPolicy
        // Typed hosts have no token to shield, so this uses the filter instead. `.specific`
        // blocks exactly these; `.auto` is deliberately avoided since it would also switch on
        // Apple's adult content filter for the whole phone. Verified on the phone 2026-09-08.
        store.webContent.blockedByFilter = decision.webFilter
        // Deny deleting apps only while something is shielded, so the flag can never outlive a block.
        store.application.denyAppRemoval = decision.isAnythingShielded ? true : nil
    }

    /// Removes every setting Furlough ever applied.
    static func clearEverything() {
        store.clearAllSettings()
        SharedStore.log("cleared all managed settings")
    }
}
