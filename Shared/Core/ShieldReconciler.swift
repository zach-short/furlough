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
        // Folded here the way due pending changes are: `Policy` has read the anchor as
        // released since its time passed, and this makes the stored flag agree in whichever
        // process reconciles first — the monitor's wake at `until` being the one that makes
        // sure some process does.
        if Policy.liftExpiredAnchor(&state.config, now: now) {
            SharedStore.log("a timed anchor's time had passed; lifted it during reconcile")
        }
        // What the Mac wrote, if anything: every wake in every process is a chance to hear of
        // a drop made elsewhere, and the merge is pure and idempotent.
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
        // The category policies and the filter are worked out on the decision, where the sets
        // they are built from live and where the three cases each has can be read together:
        // nothing, the blocked categories with the open apps excepted, or — with the anchor
        // over the whole phone — `.all(except:)` the allowlist.
        store.shield.applicationCategories = decision.appCategoryPolicy
        store.shield.webDomains = decision.shieldedWeb.isEmpty ? nil : decision.shieldedWeb
        store.shield.webDomainCategories = decision.webCategoryPolicy
        // Typed hosts, which have no token to shield. `.specific` names exactly these and
        // touches nothing else: verified on the phone 2026-09-08 with a throwaway store —
        // example.com showed iOS's own "Website Not Allowed" page while amazon.com loaded, and
        // Screen Time's system-wide content filter stayed as it was. `.auto` is the case that
        // would have switched Apple's adult filter on for the whole phone; it is not used.
        // `.all(except:)` is, while the anchor holds everything: see `Decision.webFilter`.
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
