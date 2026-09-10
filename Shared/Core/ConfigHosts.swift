import Foundation

extension Config {
    /// Whether any website is spoken for anywhere in this config — as a target of its own, as a
    /// site linked to an app, or on the anchor's list.
    ///
    /// The condition the Mac's web filter is worth anything under, and the reason it is asked
    /// for at the first website rather than during the first run: everything that holds a site
    /// on the Mac holds it by reading a browser Furlough recognises, so until one of these is
    /// true there is nothing for a filter to refuse and nobody to ask. `Enforcer` already gates
    /// its browser reads on the same fact. See `MacModel.shouldOfferWebFilter`.
    ///
    /// It counts the anchor's list too, because a site held by the anchor is exactly as
    /// unenforceable in a browser Furlough has never met as one held by a rule.
    ///
    /// In a file of its own rather than beside the other `Config` helpers because it is small,
    /// self-contained and was written in a lane running alongside another one editing
    /// `Models.swift`; fold it in there when the two meet.
    var hasAnyHost: Bool {
        targets.contains { !$0.hosts.isEmpty } || anchor.kinds.contains(where: \.isHost)
    }
}
