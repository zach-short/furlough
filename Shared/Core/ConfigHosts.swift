import Foundation

extension Config {
    /// The condition under which the Mac's web filter is worth asking for — see
    /// `MacModel.shouldOfferWebFilter`; `Enforcer` gates its own browser reads on the same
    /// fact. Includes the anchor's list, since a site held only by the anchor is equally
    /// unenforceable without a recognized browser.
    var hasAnyHost: Bool {
        targets.contains { !$0.hosts.isEmpty } || anchor.kinds.contains(where: \.isHost)
    }
}
