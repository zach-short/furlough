import Foundation
import Testing

/// `protocol/` checked against the code it describes.
///
/// The vectors in `protocol/fixtures/` are the link contract in a form a Kotlin or C# engine can
/// load: hand-written inputs, and expectations written by *this* code. Every one of them is run
/// here against the real function, so the two cannot drift — a behaviour change fails these
/// tests until somebody regenerates on purpose, and the diff of the fixtures is the review.
///
/// With `FURLOUGH_WRITE_FIXTURES=1` in the environment every `expected` is rewritten from the
/// current behaviour instead of asserted, and so are the tables under `protocol/tables/`. That is
/// the only way a fixture's expectation is ever written; nothing here is hand-maintained on both
/// sides.
///
/// The files are found from `#filePath` rather than added to the test bundle's resources, so
/// `project.yml` stays untouched and a fixture can be edited without regenerating the project.
enum ProtocolFixtures {
    /// The repo's `protocol/` directory, from this file's own path: `Tests/Core`, up two, then in.
    static var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/Core
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the repo
            .appendingPathComponent("protocol")
    }

    static var isWriting: Bool { ProcessInfo.processInfo.environment["FURLOUGH_WRITE_FIXTURES"] == "1" }

    /// The store's own encoding: ISO-8601 dates, the way `AnchorCloud` writes and reads.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// One vector: the whole file, with `input` and `expected` back as `Data` so each test can
    /// decode them into whatever that function takes and answers.
    struct File {
        var url: URL
        var name: String
        var function: String
        var input: Data
        /// Nil for a vector whose expectation has never been generated. Asserting one is an
        /// error rather than a pass: a fixture nobody has run is not evidence of anything.
        var expected: Data?

        var label: String { "\(url.lastPathComponent): \(name)" }

        /// Runs `body` on the decoded input and either asserts the answer or writes it down.
        func check<Input: Decodable, Expected: Codable & Equatable>(
            _ type: Input.Type,
            _ body: (Input) throws -> Expected
        ) throws {
            let actual = try body(ProtocolFixtures.decoder.decode(Input.self, from: input))
            guard !ProtocolFixtures.isWriting else { return try write(actual) }
            guard let expected else {
                Issue.record("\(label) has no expectation yet — run with FURLOUGH_WRITE_FIXTURES=1")
                return
            }
            #expect(actual == (try ProtocolFixtures.decoder.decode(Expected.self, from: expected)), "\(label)")
        }

        /// Rewrites the file with a freshly generated `expected`, leaving `name`, `function` and
        /// `input` as they are. Serialised sorted and pretty so two runs of the same code produce
        /// the same bytes and a real change is the only thing that shows in a diff.
        private func write(_ value: some Encodable) throws {
            var object = try ProtocolFixtures.object(at: url)
            object["expected"] = try JSONSerialization.jsonObject(with: ProtocolFixtures.encoder.encode(value))
            try ProtocolFixtures.save(object, to: url)
        }
    }

    static func object(at url: URL) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw Failure("\(url.lastPathComponent) is not a JSON object")
        }
        return object
    }

    static func save(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try (String(decoding: data, as: UTF8.self) + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Every vector in one folder of `fixtures/`, by filename.
    static func files(in folder: String) throws -> [File] {
        let directory = root.appendingPathComponent("fixtures").appendingPathComponent(folder)
        let urls = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { url in
            let object = try ProtocolFixtures.object(at: url)
            guard let name = object["name"] as? String, let function = object["function"] as? String else {
                throw Failure("\(url.lastPathComponent) needs a name and a function")
            }
            guard let input = object["input"] else { throw Failure("\(url.lastPathComponent) needs an input") }
            return File(
                url: url,
                name: name,
                function: function,
                input: try JSONSerialization.data(withJSONObject: input),
                expected: try object["expected"].map { try JSONSerialization.data(withJSONObject: $0) }
            )
        }
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: The enums, listed so the compiler stops here when a case is added

    /// Each of these carries an exhaustive `switch` whose only job is to fail to compile when a
    /// case appears that the schema's `enum` list and the vectors below do not know about. A
    /// plain literal array would silently go on passing.

    static func name(of refusal: Policy.DropRefusal) -> String {
        switch refusal {
        case .alreadyAnchored: "alreadyAnchored"
        case .nothingToAnchor: "nothingToAnchor"
        case .tooSoon: "tooSoon"
        case .noList: "noList"
        case .noPhone: "noPhone"
        case .noCloud: "noCloud"
        }
    }

    static func name(of refusal: DeviceLink.LeaveRefusal) -> String {
        switch refusal {
        case .anchored: "anchored"
        }
    }

    static let platforms: [AnchorRecord.Platform] = {
        func exhaustive(_ platform: AnchorRecord.Platform) {
            switch platform { case .phone, .pad, .mac: break }
        }
        return [.phone, .pad, .mac]
    }()

    static let origins: [AnchorRecord.Origin] = {
        func exhaustive(_ origin: AnchorRecord.Origin) {
            switch origin { case .drop, .tagScan, .lift: break }
        }
        return [.drop, .tagScan, .lift]
    }()

    static let halves: [Half] = {
        func exhaustive(_ half: Half) {
            switch half { case .rules, .anchor: break }
        }
        return [.rules, .anchor]
    }()

    static let exportPlatforms: [ConfigExport.Platform] = {
        func exhaustive(_ platform: ConfigExport.Platform) {
            switch platform { case .iOS, .mac: break }
        }
        return [.iOS, .mac]
    }()

    static let exportKinds: [ExportedTarget.Kind] = {
        func exhaustive(_ kind: ExportedTarget.Kind) {
            switch kind { case .app, .website, .category: break }
        }
        return [.app, .website, .category]
    }()

    static let tiers: [ExportedTarget.Tier] = {
        func exhaustive(_ tier: ExportedTarget.Tier) {
            switch tier { case .essential, .useful, .idle, .hazard: break }
        }
        return [.essential, .useful, .idle, .hazard]
    }()
}

// MARK: - The anchor's merge

private struct MergeInput: Decodable {
    var local: AnchorProfile
    var remote: AnchorRecord
    var now: Date
}

private struct MergeExpected: Codable, Equatable {
    var profile: AnchorProfile
    var note: String
}

@Suite("Protocol vectors: merging the anchor")
struct ProtocolMergeTests {
    @Test("every branch of AnchorSync.merge")
    func merge() throws {
        let files = try ProtocolFixtures.files(in: "merge")
        #expect(files.count == 11)
        for file in files {
            switch file.function {
            case "AnchorSync.merge":
                try file.check(MergeInput.self) { input in
                    let merged = AnchorSync.merge(local: input.local, remote: input.remote, now: input.now)
                    return MergeExpected(profile: merged.profile, note: merged.note)
                }
            default:
                Issue.record("\(file.label): no runner for \(file.function)")
            }
        }
    }
}

// MARK: - The Mac's drop

private struct MacDropInput: Decodable {
    var config: Config
    var now: Date
    var hasKey: Bool
    var cloudAvailable: Bool
}

private struct MacDropExpected: Codable, Equatable {
    /// The refusal's case name, or nil when the drop went through.
    var refusal: String?
    /// The sentence that refusal shows, so a port renders the same words.
    var message: String?
    /// The anchor as `macDrop` left it. The whole of what it mutates.
    var anchor: AnchorProfile
}

@Suite("Protocol vectors: the Mac's drop")
struct ProtocolMacDropTests {
    @Test("every refusal of AnchorSync.macDrop, and the drop itself")
    func macDrop() throws {
        let files = try ProtocolFixtures.files(in: "mac-drop")
        #expect(files.count == 6)
        for file in files {
            switch file.function {
            case "AnchorSync.macDrop":
                try file.check(MacDropInput.self) { input in
                    var config = input.config
                    let refusal = AnchorSync.macDrop(
                        &config, now: input.now, hasKey: input.hasKey, cloudAvailable: input.cloudAvailable
                    )
                    return MacDropExpected(
                        refusal: refusal.map(ProtocolFixtures.name(of:)),
                        message: refusal?.message,
                        anchor: config.anchor
                    )
                }
            default:
                Issue.record("\(file.label): no runner for \(file.function)")
            }
        }
    }
}

// MARK: - The roster, and leaving

private struct RosterInput: Decodable {
    var devices: [LinkedDevice]
    var revoked: [String: Revocation]
    /// Only for `hasKey`: the device asking.
    var besides: String?

    var roster: DeviceLink.Roster { DeviceLink.Roster(devices: devices, revoked: revoked) }
}

private struct LinkedExpected: Codable, Equatable {
    /// The ids on the link, in the order `linked` returns them.
    var linked: [String]
}

private struct HasKeyExpected: Codable, Equatable {
    var hasKey: Bool
    /// The sentence that names the others, since a port has to word it the same way.
    var others: String
}

private struct LeaveInput: Decodable {
    var anchorHoldsHere: Bool
    var anchorHoldsOnLink: Bool
}

private struct LeaveExpected: Codable, Equatable {
    var refusal: String?
    var message: String?
}

@Suite("Protocol vectors: the roster")
struct ProtocolRosterTests {
    @Test("Roster.linked, hasKey and the refusal to leave")
    func roster() throws {
        let files = try ProtocolFixtures.files(in: "roster")
        #expect(files.count == 9)
        for file in files {
            switch file.function {
            case "Roster.linked":
                try file.check(RosterInput.self) { LinkedExpected(linked: $0.roster.linked.map(\.id)) }
            case "Roster.hasKey":
                try file.check(RosterInput.self) { input in
                    let id = input.besides ?? ""
                    return HasKeyExpected(
                        hasKey: input.roster.hasKey(besides: id),
                        others: input.roster.othersDescription(than: id)
                    )
                }
            case "DeviceLink.leaveRefusal":
                try file.check(LeaveInput.self) { input in
                    let refusal = DeviceLink.leaveRefusal(
                        anchorHoldsHere: input.anchorHoldsHere, anchorHoldsOnLink: input.anchorHoldsOnLink
                    )
                    return LeaveExpected(refusal: refusal.map(ProtocolFixtures.name(of:)), message: refusal?.message)
                }
            default:
                Issue.record("\(file.label): no runner for \(file.function)")
            }
        }
    }
}

// MARK: - The ring, the watermark, and what an arrival would do

private struct AppendedInput: Decodable {
    var ring: [SharedAddition]
    var addition: SharedAddition
}

/// `appended` decides which entries survive and in what order; it never alters one. So the
/// expectation is that decision rather than twenty copied-out records.
private struct RingEntry: Codable, Equatable {
    var id: String
    var sequence: Int
}

private struct AppendedExpected: Codable, Equatable {
    var ring: [RingEntry]
}

private struct UnseenInput: Decodable {
    var thisDevice: String
    var rings: [String: [SharedAddition]]
    var watermarks: [String: Int]
    var declined: [String]
    var devices: [LinkedDevice]
    var revoked: [String: Revocation]
}

private struct UnseenEntry: Codable, Equatable {
    var origin: String
    var sequence: Int
    var title: String
}

private struct UnseenExpected: Codable, Equatable {
    var unseen: [UnseenEntry]
}

private struct LandingInput: Decodable {
    var addition: SharedAddition
    var config: Config
    /// This Mac's applications, normalised bundle identifier to name. Empty on a phone.
    var installed: [String: String]
    var companion: LinkChoice
    /// What the sending device is called, for the offer's sentence.
    var from: String
    /// The clock the anchor is read against — an addition to the anchor's half is not taken
    /// into the list while the anchor is holding. Fixed in every fixture, never now.
    var now: Date
}

private struct LandingExpected: Codable, Equatable {
    var existing: String?
    var appBundleID: String?
    var appName: String?
    var hosts: [String]
    var appNeedsPicker: Bool
    var rule: Rule?
    /// Whether landing this would also put the rows into this device's anchor list.
    var anchors: Bool
    var isNothing: Bool
    var summary: String
}

@Suite("Protocol vectors: what crosses when you add something")
struct ProtocolAdditionsTests {
    @Test("the ring, the watermark, and the landing")
    func additions() throws {
        let files = try ProtocolFixtures.files(in: "additions")
        #expect(files.count == 16)
        for file in files {
            switch file.function {
            case "SharedAdditions.appended":
                try file.check(AppendedInput.self) { input in
                    AppendedExpected(
                        ring: SharedAdditions.appended(input.ring, input.addition)
                            .map { RingEntry(id: $0.id.uuidString, sequence: $0.sequence) }
                    )
                }
            case "SharedAdditions.unseen":
                try file.check(UnseenInput.self) { input in
                    UnseenExpected(
                        unseen: SharedAdditions.unseen(
                            rings: input.rings,
                            watermarks: input.watermarks,
                            declined: Set(input.declined),
                            thisDevice: input.thisDevice,
                            roster: DeviceLink.Roster(devices: input.devices, revoked: input.revoked)
                        )
                        .map { UnseenEntry(origin: $0.origin, sequence: $0.sequence, title: $0.title) }
                    )
                }
            case "SharedAdditions.landing":
                try file.check(LandingInput.self) { input in
                    let landing = SharedAdditions.landing(
                        for: input.addition,
                        in: input.config,
                        installed: input.installed,
                        companion: input.companion,
                        now: input.now
                    )
                    return LandingExpected(
                        existing: landing.existing?.uuidString,
                        appBundleID: landing.appBundleID,
                        appName: landing.appName,
                        hosts: landing.hosts,
                        appNeedsPicker: landing.appNeedsPicker,
                        rule: landing.rule,
                        anchors: landing.anchors,
                        isNothing: landing.isNothing,
                        summary: landing.summary(from: input.from)
                    )
                }
            default:
                Issue.record("\(file.label): no runner for \(file.function)")
            }
        }
    }
}

// MARK: - The schemas

/// Checks a schema against what the encoder actually writes: every key written is a property the
/// schema names, and every property the schema requires is written. Recursive, so `Rule` and
/// `TimeWindow` under a `SharedAddition` and `ExportedTarget` under a `ConfigExport` are checked
/// too, whether the `$ref` points inside the file or at another one.
///
/// Deliberately not a JSON Schema library. The question here is narrow — do these two files
/// describe the same object — and a walk over `properties` answers it without a dependency, which
/// this project does not take.
enum SchemaCheck {
    static func schema(_ file: String) throws -> [String: Any] {
        try ProtocolFixtures.object(at: ProtocolFixtures.root.appendingPathComponent("schema").appendingPathComponent(file))
    }

    /// Resolves a `$ref`: `#/$defs/rule` inside `file`, or `other.json#/$defs/rule` in another.
    static func resolve(_ node: [String: Any], in file: String) throws -> ([String: Any], String) {
        guard let ref = node["$ref"] as? String else { return (node, file) }
        let parts = ref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let target = parts[0].isEmpty ? file : String(parts[0])
        var node = try schema(target)
        for key in parts[1].split(separator: "/") where key != "" {
            guard let next = node[String(key)] as? [String: Any] else {
                throw ProtocolFixtures.Failure("\(target) has nothing at \(ref)")
            }
            node = next
        }
        return (node, target)
    }

    static func walk(_ value: Any, against node: [String: Any], in file: String, at path: String) throws {
        let (node, file) = try resolve(node, in: file)
        if let object = value as? [String: Any] {
            guard let properties = node["properties"] as? [String: Any] else { return }
            for key in object.keys.sorted() {
                guard let property = properties[key] as? [String: Any] else {
                    Issue.record("\(file): the encoder writes \(path)\(key), which the schema does not name")
                    continue
                }
                try walk(object[key]!, against: property, in: file, at: "\(path)\(key).")
            }
            for required in (node["required"] as? [String] ?? []) where object[required] == nil {
                Issue.record("\(file): the schema requires \(path)\(required), which the encoder did not write")
            }
        } else if let array = value as? [Any], let items = node["items"] as? [String: Any] {
            for element in array { try walk(element, against: items, in: file, at: path) }
        }
    }

    static func check(_ file: String, encoding value: some Encodable) throws {
        try walk(
            try JSONSerialization.jsonObject(with: ProtocolFixtures.encoder.encode(value)),
            against: try schema(file),
            in: file,
            at: ""
        )
    }

    /// The `enum` list at a slash-separated path inside a schema.
    static func values(_ file: String, at path: String) throws -> [String] {
        var node = try schema(file)
        for key in path.split(separator: "/") {
            guard let next = node[String(key)] as? [String: Any] else {
                throw ProtocolFixtures.Failure("\(file) has nothing at \(path)")
            }
            node = next
        }
        guard let values = node["enum"] as? [String] else {
            throw ProtocolFixtures.Failure("\(file) has no enum at \(path)")
        }
        return values
    }
}

@Suite("Protocol schemas")
struct ProtocolSchemaTests {
    /// Every optional filled in, so a schema cannot hide a property by being handed a sample that
    /// never writes one.
    private var record: AnchorRecord {
        AnchorRecord(
            sequence: 4,
            isAnchored: true,
            anchoredAt: at(8, 9),
            until: at(8, 15),
            writer: "phone-a",
            platform: .phone,
            origin: .drop,
            writtenAt: at(8, 9)
        )
    }

    private var device: LinkedDevice {
        LinkedDevice(
            id: "phone-a", name: "Zach's iPhone", platform: .phone,
            enrolledAt: at(7), lastSeen: at(8), canRelease: true
        )
    }

    private var addition: SharedAddition {
        SharedAddition(
            id: UUID(),
            sequence: 3,
            title: "YouTube",
            isApp: true,
            bundleIDs: ["com.google.ios.youtube"],
            hosts: ["youtube.com"],
            rule: Rule(
                windows: [window(9 * 60, 22 * 60)],
                dailyBudgetMinutes: 30,
                budgetByWeekday: [30, 30, 30, 30, 30, 60, 60]
            ),
            half: .rules,
            origin: "phone-a",
            platform: .phone,
            addedAt: at(8, 9)
        )
    }

    private var export: ConfigExport {
        var target = Target(kind: .host("youtube.com"), nickname: "YouTube", rule: Rule(dailyBudgetMinutes: 30))
        target.systemName = "YouTube"
        target.also = [.host("m.youtube.com")]
        target.utilityLevel = .hazard
        return ConfigExport(
            version: 1,
            platform: .mac,
            exportedAt: at(8),
            appVersion: "1.0.1",
            loosenDelayHours: 24,
            targets: [ExportedTarget(target)]
        )
    }

    @Test("every key the encoder writes is a property the schema names")
    func properties() throws {
        try SchemaCheck.check("anchor-record.json", encoding: record)
        try SchemaCheck.check("linked-device.json", encoding: device)
        try SchemaCheck.check("revocation.json", encoding: Revocation(by: "mac-a", at: at(8)))
        try SchemaCheck.check("shared-addition.json", encoding: addition)
        try SchemaCheck.check("config-export.json", encoding: export)
    }

    @Test("every enum's raw values are the schema's enum list")
    func enums() throws {
        let platforms = ProtocolFixtures.platforms.map(\.rawValue)
        #expect(try SchemaCheck.values("anchor-record.json", at: "properties/platform") == platforms)
        #expect(try SchemaCheck.values("linked-device.json", at: "properties/platform") == platforms)
        #expect(try SchemaCheck.values("shared-addition.json", at: "properties/platform") == platforms)
        #expect(
            try SchemaCheck.values("anchor-record.json", at: "properties/origin")
                == ProtocolFixtures.origins.map(\.rawValue)
        )
        #expect(
            try SchemaCheck.values("shared-addition.json", at: "properties/half")
                == ProtocolFixtures.halves.map(\.rawValue)
        )
        #expect(
            try SchemaCheck.values("config-export.json", at: "properties/platform")
                == ProtocolFixtures.exportPlatforms.map(\.rawValue)
        )
        #expect(
            try SchemaCheck.values("config-export.json", at: "$defs/exportedTarget/properties/kind")
                == ProtocolFixtures.exportKinds.map(\.rawValue)
        )
        #expect(
            try SchemaCheck.values("config-export.json", at: "$defs/exportedTarget/properties/utility")
                == ProtocolFixtures.tiers.map(\.rawValue)
        )
    }
}

// MARK: - The tables

private struct CompanionRow: Codable, Equatable {
    var title: String
    var names: [String]
    var bundleIDs: [String]
    var hosts: [String]
}

private struct TierRow: Codable, Equatable {
    var key: String
    var utility: String
    var detail: String?
}

private struct TierTables: Codable, Equatable {
    var names: [TierRow]
    var bundleIDs: [TierRow]
    var bundleIDPrefixes: [TierRow]
    var hosts: [TierRow]
}

private struct SuggestionRow: Codable, Equatable {
    var key: String
    var utility: String
    var budgetMinutes: Int
    var window: TimeWindow?
}

private struct SuggestionTables: Codable, Equatable {
    var names: [SuggestionRow]
    var bundleIDs: [SuggestionRow]
    var hosts: [SuggestionRow]
}

@Suite("Protocol tables")
struct ProtocolTableTests {
    private func table(_ file: String) -> URL {
        ProtocolFixtures.root.appendingPathComponent("tables").appendingPathComponent(file)
    }

    /// Compares a dumped table with the Swift it came from, or rewrites it under the flag.
    private func check<Value: Codable & Equatable>(_ file: String, _ value: Value) throws {
        let url = table(file)
        guard !ProtocolFixtures.isWriting else {
            return try ProtocolFixtures.save(try JSONSerialization.jsonObject(with: ProtocolFixtures.encoder.encode(value)), to: url)
        }
        let stored = try ProtocolFixtures.decoder.decode(Value.self, from: Data(contentsOf: url))
        #expect(stored == value, "\(file) is out of date — run with FURLOUGH_WRITE_FIXTURES=1")
    }

    private func rows(_ table: [String: AppUtility.Advice]) -> [TierRow] {
        table.keys.sorted().map {
            TierRow(key: $0, utility: ExportedTarget.Tier(table[$0]!.utility).rawValue, detail: table[$0]!.detail)
        }
    }

    private func rows(_ table: [(host: String, value: AppUtility.Advice)]) -> [TierRow] {
        table.map { TierRow(key: $0.host, utility: ExportedTarget.Tier($0.value.utility).rawValue, detail: $0.value.detail) }
    }

    private func rows(_ table: [(prefix: String, value: AppUtility.Advice)]) -> [TierRow] {
        table.map { TierRow(key: $0.prefix, utility: ExportedTarget.Tier($0.value.utility).rawValue, detail: $0.value.detail) }
    }

    private func rows(_ table: [String: RuleSuggestion.Exception]) -> [SuggestionRow] {
        table.keys.sorted().map { row(key: $0, table[$0]!) }
    }

    private func rows(_ table: [(host: String, value: RuleSuggestion.Exception)]) -> [SuggestionRow] {
        table.map { row(key: $0.host, $0.value) }
    }

    private func row(key: String, _ exception: RuleSuggestion.Exception) -> SuggestionRow {
        SuggestionRow(
            key: key,
            utility: ExportedTarget.Tier(exception.utility).rawValue,
            budgetMinutes: exception.draft.budgetMinutes,
            window: exception.draft.window
        )
    }

    @Test("the companion pairs, in table order")
    func companions() throws {
        try check(
            "companions.json",
            Companions.pairs.map {
                CompanionRow(title: $0.title, names: $0.names, bundleIDs: $0.bundleIDs, hosts: $0.hosts)
            }
        )
    }

    @Test("the tier table")
    func tiers() throws {
        try check(
            "tiers.json",
            TierTables(
                names: rows(AppUtility.names),
                bundleIDs: rows(AppUtility.bundleIDs),
                bundleIDPrefixes: rows(AppUtility.bundleIDPrefixes),
                hosts: rows(AppUtility.hosts)
            )
        )
    }

    @Test("the starting rules")
    func ruleSuggestions() throws {
        try check(
            "rule-suggestions.json",
            SuggestionTables(
                names: rows(RuleSuggestion.names),
                bundleIDs: rows(RuleSuggestion.bundleIDs),
                hosts: rows(RuleSuggestion.hosts)
            )
        )
    }

    /// The one table that is not generated: what each companion pair is called on Android and
    /// Windows, filled in by hand from a confirmed vendor source. So the check is the only thing
    /// a machine can check — that every key is a pair that actually exists — and never that the
    /// values are right.
    @Test("every key of other-platforms is a real companion title")
    func otherPlatforms() throws {
        let object = try ProtocolFixtures.object(at: table("other-platforms.json"))
        let titles = Set(Companions.pairs.map(\.title))
        // A `$`-prefixed key is a note to whoever opens the file, not an entry. JSON has no
        // comments and this one needs to say why it is empty.
        for key in object.keys.sorted() where !key.hasPrefix("$") && !titles.contains(key) {
            Issue.record("other-platforms.json names \(key), which is not a companion pair")
        }
    }
}

// MARK: - The rules engine

/// `NextOpen` is `Equatable` and not `Codable`, and `TargetStatus` is an enum with associated
/// values whose synthesised encoding would be an implementation detail rather than a contract.
/// So both are written out as plain tagged objects a port can read.
private struct NextOpenJSON: Codable, Equatable {
    var minuteOfDay: Int
    var daysAhead: Int

    init(_ next: NextOpen) {
        minuteOfDay = next.minuteOfDay
        daysAhead = next.daysAhead
    }
}

private struct StatusExpected: Codable, Equatable {
    var status = ""
    /// `.open` only: the window's end minute, past 1440 for a night.
    var until: Int?
    /// `.closed` and `.exhausted`.
    var nextOpen: NextOpenJSON?
    /// Whether this status lets the thing through, which is the whole question a shield asks.
    var isAllowed = false

    init(_ status: TargetStatus) {
        isAllowed = status.isAllowed
        switch status {
        case .anchored: self.status = "anchored"
        case .unconfigured: self.status = "unconfigured"
        case .blockedAllDay: self.status = "blockedAllDay"
        case .open(let until):
            self.status = "open"
            self.until = until
        case .exhausted(let next):
            self.status = "exhausted"
            nextOpen = next.map(NextOpenJSON.init)
        case .closed(let next):
            self.status = "closed"
            nextOpen = NextOpenJSON(next)
        }
    }
}

private struct StatusInput: Decodable {
    var config: Config
    /// Which of `config.targets` to ask about. It has to be in the config: whether the anchor
    /// holds it is read from `config.anchor`.
    var targetID: UUID
    var runtime: RuntimeState
    var now: Date
}

private struct TransitionInput: Decodable {
    var config: Config
    var now: Date
}

private struct TransitionExpected: Codable, Equatable {
    var at: Date
}

private struct ClassifyRuleInput: Decodable {
    /// Absent means removing the rule, which is `Rule.unrestricted` — everything allowed.
    var newRule: Rule?
    /// Absent means a target that does not exist yet, whose rule is also unrestricted.
    var target: Target?
}

private struct ClassifyUtilityInput: Decodable {
    /// The tier by its word rather than the store's number, so a vector reads.
    var newUtility: ExportedTarget.Tier
    /// The tier the target already carries; absent for one nobody has tiered, which is `useful`.
    var targetUtility: ExportedTarget.Tier?
}

private struct ClassifyExpected: Codable, Equatable {
    var classification: String

    init(_ change: ChangeClass) {
        switch change {
        case .tightening: classification = "tightening"
        case .loosening: classification = "loosening"
        }
    }
}

private struct PendingInput: Decodable {
    var state: SharedState
    var now: Date
}

private struct PendingExpected: Codable, Equatable {
    var changed: Bool
    /// The whole config afterwards: what a pending change lands *is* the config, so there is no
    /// projection of it that would be less than the thing itself.
    var config: Config
    /// The ids still waiting, in the order they are left in.
    var pendingLeft: [String]
    /// `applyDuePending` is also the one place a landing is counted into the record. A port that
    /// implemented only the config half would pass every other assertion and lose the count.
    var landedToday: Int
}

private struct WindowsInput: Decodable {
    var windows: [TimeWindow]
}

private struct WindowsExpected: Codable, Equatable {
    var windows: [TimeWindow]
}

private struct WeekInput: Decodable {
    var rule: Rule
}

/// A whole rule read a day at a time, Sunday first — the shape of the answer a per-weekday
/// budget exists to give.
private struct WeekExpected: Codable, Equatable {
    var budgets: [Int]
    var everAllowed: [Bool]
    var windowsPerDay: [Int]
    var effectiveBudgets: [Int]
    var representativeBudget: Int
    var isSameBudgetEveryDay: Bool
    /// What an editor saves: seven equal days collapse back to the one number.
    var normalized: Rule
}

private struct SpansInput: Decodable {
    var state: SharedState
}

private struct SpansExpected: Codable, Equatable {
    var spans: [TimeWindow]
}

/// The rules engine, as vectors.
///
/// Everything here is computed in `cal` — Gregorian, GMT, en_US_POSIX, Sunday first — and every
/// date in a fixture is a fixed ISO-8601 string in that calendar. A port has to pin its own the
/// same way before comparing: `minuteOfDay`, `weekday` and the day boundary all move with the
/// time zone, and weekday numbers here are Calendar's, 1 = Sunday … 7 = Saturday, which is also
/// how `TimeWindow.days` numbers its bits.
@Suite("Protocol vectors: the rules engine")
struct ProtocolPolicyTests {
    @Test("status, the next transition, tightening against loosening, pending, nights and weekday budgets")
    func policy() throws {
        let files = try ProtocolFixtures.files(in: "policy")
        #expect(files.count == 48)
        for file in files {
            switch file.function {
            case "Policy.status":
                try file.check(StatusInput.self) { input in
                    guard let target = input.config.target(id: input.targetID) else {
                        throw ProtocolFixtures.Failure("no target \(input.targetID) in the config")
                    }
                    return StatusExpected(
                        Policy.status(
                            of: target, config: input.config, runtime: input.runtime,
                            now: input.now, calendar: cal
                        )
                    )
                }
            case "Policy.nextTransition":
                try file.check(TransitionInput.self) { input in
                    TransitionExpected(
                        at: Policy.nextTransition(config: input.config, after: input.now, calendar: cal)
                    )
                }
            case "Policy.classify(newRule:)":
                try file.check(ClassifyRuleInput.self) {
                    ClassifyExpected(Policy.classify(newRule: $0.newRule, against: $0.target))
                }
            case "Policy.classify(newUtility:)":
                try file.check(ClassifyUtilityInput.self) { input in
                    var target = Target(kind: .host("example.com"))
                    target.utilityLevel = input.targetUtility?.utility
                    return ClassifyExpected(
                        Policy.classify(
                            newUtility: input.newUtility.utility,
                            against: input.targetUtility == nil ? nil : target
                        )
                    )
                }
            case "Policy.applyDuePending":
                try file.check(PendingInput.self) { input in
                    var state = input.state
                    let changed = Policy.applyDuePending(&state, now: input.now, calendar: cal)
                    return PendingExpected(
                        changed: changed,
                        config: state.config,
                        pendingLeft: state.pending.map(\.id.uuidString),
                        landedToday: state.runtime.days[Policy.dayKey(input.now, calendar: cal)]?.landed ?? 0
                    )
                }
            case "TimeWindow.split":
                try file.check(WindowsInput.self) { WindowsExpected(windows: $0.windows.flatMap(\.split)) }
            case "TimeWindow.folded":
                try file.check(WindowsInput.self) { WindowsExpected(windows: TimeWindow.folded($0.windows)) }
            case "Rule.week":
                try file.check(WeekInput.self) { input in
                    let rule = input.rule
                    return WeekExpected(
                        budgets: (1...7).map { rule.budget(on: $0) },
                        everAllowed: (1...7).map { rule.isEverAllowed(on: $0) },
                        windowsPerDay: (1...7).map { rule.windows(on: $0).count },
                        effectiveBudgets: (1...7).map { rule.effectiveBudget(on: $0) },
                        representativeBudget: rule.representativeBudget,
                        isSameBudgetEveryDay: rule.isSameBudgetEveryDay,
                        normalized: rule.normalized
                    )
                }
            case "ActivityLimit.spans":
                try file.check(SpansInput.self) { SpansExpected(spans: ActivityLimit.spans(in: $0.state).sorted()) }
            default:
                Issue.record("\(file.label): no runner for \(file.function)")
            }
        }
    }
}
