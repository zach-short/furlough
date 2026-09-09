import Foundation
import Testing

/// The web filter's decisions: the rules the app pushes, what a connection shows the moment it
/// opens, and the name read out of its first bytes.
struct FlowRulesTests {
    private let now = at(8, 12, 0)
    private var rules: FilterRules {
        FilterRules(hosts: ["youtube.com", "reddit.com"], until: at(8, 22, 0), version: 3)
    }

    // MARK: The rules themselves

    @Test func rulesLapseAtTheirHorizon() {
        #expect(rules.isCurrent(at: at(8, 21, 59)))
        #expect(!rules.isCurrent(at: at(8, 22, 0)))
        #expect(rules.activeHosts(at: at(8, 21, 59)) == ["youtube.com", "reddit.com"])
        #expect(rules.activeHosts(at: at(8, 22, 0)).isEmpty)
    }

    @Test func rulesSurviveTheTripThroughTheVendorConfiguration() {
        #expect(FilterRules(vendorConfiguration: rules.vendorConfiguration) == rules)
        #expect(FilterRules(vendorConfiguration: nil) == nil)
        #expect(FilterRules(vendorConfiguration: ["hosts": 3]) == nil)
        #expect(FilterRules(vendorConfiguration: ["hosts": ["a.com"], "until": "tomorrow", "version": 1]) == nil)
    }

    // MARK: What a connection looks like as it opens

    @Test func aNameIsLoweredAndAnAddressIsNoName() {
        #expect(FlowRules.Endpoint(hostname: "M.YouTube.com", port: 443, isUDP: false).hostname == "m.youtube.com")
        #expect(FlowRules.Endpoint(hostname: "142.250.72.14", port: 443, isUDP: false).hostname == nil)
        #expect(FlowRules.Endpoint(hostname: "2607:f8b0:4004:800::200e", port: 443, isUDP: false).hostname == nil)
        #expect(FlowRules.Endpoint(hostname: "", port: 443, isUDP: false).hostname == nil)
    }

    @Test func nothingBlockedMeansEverythingAllowed() {
        let empty = FilterRules(hosts: [], until: at(8, 22, 0), version: 1)
        #expect(FlowRules.newFlow(.init(hostname: "youtube.com", port: 443, isUDP: false), rules: empty, now: now) == .allow)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 443, isUDP: true), rules: empty, now: now) == .allow)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 443, isUDP: false), rules: empty, now: now) == .allow)
    }

    @Test func lapsedRulesBlockNothing() {
        let later = at(8, 23, 0)
        #expect(FlowRules.newFlow(.init(hostname: "youtube.com", port: 443, isUDP: false), rules: rules, now: later) == .allow)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 443, isUDP: true), rules: rules, now: later) == .allow)
    }

    @Test func aNamedConnectionIsDecidedOnItsName() {
        #expect(FlowRules.newFlow(.init(hostname: "youtube.com", port: 443, isUDP: false), rules: rules, now: now)
            == .drop(host: "youtube.com", rule: "youtube.com"))
        #expect(FlowRules.newFlow(.init(hostname: "m.youtube.com", port: 443, isUDP: false), rules: rules, now: now)
            == .drop(host: "m.youtube.com", rule: "youtube.com"))
        #expect(FlowRules.newFlow(.init(hostname: "www.reddit.com", port: 80, isUDP: false), rules: rules, now: now)
            == .drop(host: "www.reddit.com", rule: "reddit.com"))
        // A name the rules do not cover is allowed without a look at its bytes, whatever the port.
        #expect(FlowRules.newFlow(.init(hostname: "notyoutube.com", port: 443, isUDP: false), rules: rules, now: now) == .allow)
        #expect(FlowRules.newFlow(.init(hostname: "example.com", port: 443, isUDP: true), rules: rules, now: now) == .allow)
        // And a named QUIC connection to a blocked host is dropped as such, not as QUIC.
        #expect(FlowRules.newFlow(.init(hostname: "youtube.com", port: 443, isUDP: true), rules: rules, now: now)
            == .drop(host: "youtube.com", rule: "youtube.com"))
    }

    @Test func aNamelessConnectionIsInspectedOnTheWebPortsOnly() {
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 443, isUDP: false), rules: rules, now: now) == .inspect)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 80, isUDP: false), rules: rules, now: now) == .inspect)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 8080, isUDP: false), rules: rules, now: now) == .allow)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 22, isUDP: false), rules: rules, now: now) == .allow)
    }

    @Test func namelessQUICIsRefusedWhileAnythingIsBlocked() {
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 443, isUDP: true), rules: rules, now: now) == .dropQUIC)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 53, isUDP: true), rules: rules, now: now) == .allow)
        #expect(FlowRules.newFlow(.init(hostname: nil, port: 80, isUDP: true), rules: rules, now: now) == .allow)
    }

    // MARK: The name in a TLS ClientHello

    @Test func theServerNameIsReadFromARealClientHello() {
        #expect(FlowRules.TLS.serverName(in: Fixtures.helloForMobileYouTube) == .found("m.youtube.com"))
        #expect(FlowRules.TLS.serverName(in: Fixtures.helloForLongName)
            == .found("a-rather-long-subdomain-name.assets.example-cdn.co.uk"))
    }

    @Test func aHelloWithoutAServerNameHasNoName() {
        #expect(FlowRules.TLS.serverName(in: Fixtures.helloWithoutName) == .absent)
    }

    @Test func aCutOffHelloAsksForMore() {
        #expect(FlowRules.TLS.serverName(in: Fixtures.helloForMobileYouTube.prefix(3)) == .incomplete)
        #expect(FlowRules.TLS.serverName(in: Fixtures.helloForMobileYouTube.prefix(100)) == .incomplete)
        #expect(FlowRules.TLS.serverName(in: Fixtures.helloForMobileYouTube.dropLast()) == .incomplete)
    }

    @Test func aHelloSplitAcrossTwoRecordsStillReads() {
        let whole = Fixtures.helloForMobileYouTube
        let handshake = whole.dropFirst(5)
        let cut = 700
        var split = Data()
        for part in [handshake.prefix(cut), handshake.dropFirst(cut)] {
            split += [0x16, 0x03, 0x03, UInt8(part.count >> 8), UInt8(part.count & 0xff)]
            split += part
        }
        #expect(FlowRules.TLS.serverName(in: split) == .found("m.youtube.com"))
        #expect(FlowRules.TLS.serverName(in: split.prefix(cut + 20)) == .incomplete)
    }

    @Test func bytesThatAreNotTLSHaveNoName() {
        #expect(FlowRules.TLS.serverName(in: Data("GET / HTTP/1.1\r\n".utf8)) == .absent)
        #expect(FlowRules.TLS.serverName(in: Data([0x16, 0x03, 0x01, 0x00, 0x00])) == .absent)
        // A handshake record that is not a ClientHello: a ServerHello type byte.
        var notHello = Fixtures.helloForMobileYouTube
        notHello[5] = 0x02
        #expect(FlowRules.TLS.serverName(in: notHello) == .absent)
    }

    // MARK: The name in an HTTP request

    @Test func theHostHeaderIsRead() {
        #expect(FlowRules.HTTP.host(in: Data("GET /watch HTTP/1.1\r\nUser-Agent: x\r\nHost: M.YouTube.com\r\n\r\n".utf8))
            == .found("m.youtube.com"))
        #expect(FlowRules.HTTP.host(in: Data("POST / HTTP/1.0\r\nhost:  reddit.com:80 \r\n\r\nbody".utf8)) == .found("reddit.com"))
        #expect(FlowRules.HTTP.host(in: Data("GET / HTTP/1.1\r\nHost: [::1]:80\r\n\r\n".utf8)) == .found("[::1]:80"))
    }

    @Test func aRequestWithoutAHostHasNoName() {
        #expect(FlowRules.HTTP.host(in: Data("GET / HTTP/1.1\r\nAccept: */*\r\n\r\n".utf8)) == .absent)
        #expect(FlowRules.HTTP.host(in: Data("GET / HTTP/1.1\r\nHost: \r\n\r\n".utf8)) == .absent)
    }

    @Test func anUnfinishedRequestAsksForMore() {
        #expect(FlowRules.HTTP.host(in: Data("GE".utf8)) == .incomplete)
        #expect(FlowRules.HTTP.host(in: Data("GET / HTTP/1.1\r\nHost: youtube.com\r\n".utf8)) == .incomplete)
    }

    @Test func bytesThatAreNotHTTPHaveNoName() {
        #expect(FlowRules.HTTP.host(in: Data("SSH-2.0-OpenSSH\r\n".utf8)) == .absent)
        #expect(FlowRules.HTTP.host(in: Data("xx".utf8)) == .absent)
        #expect(FlowRules.HTTP.host(in: Fixtures.helloForMobileYouTube) == .absent)
    }

    // MARK: Inspection, end to end

    @Test func aBlockedNameInTheFirstBytesDropsTheConnection() {
        #expect(FlowRules.inspect(Fixtures.helloForMobileYouTube, port: 443, rules: rules, now: now)
            == .drop(host: "m.youtube.com", rule: "youtube.com"))
        #expect(FlowRules.inspect(Data("GET / HTTP/1.1\r\nHost: old.reddit.com\r\n\r\n".utf8), port: 80, rules: rules, now: now)
            == .drop(host: "old.reddit.com", rule: "reddit.com"))
    }

    @Test func anAllowedOrMissingNameLetsTheConnectionThrough() {
        #expect(FlowRules.inspect(Fixtures.helloForLongName, port: 443, rules: rules, now: now) == .allow)
        #expect(FlowRules.inspect(Fixtures.helloWithoutName, port: 443, rules: rules, now: now) == .allow)
        #expect(FlowRules.inspect(Data("nonsense".utf8), port: 443, rules: rules, now: now) == .allow)
        #expect(FlowRules.inspect(Data("GET / HTTP/1.1\r\n\r\n".utf8), port: 80, rules: rules, now: now) == .allow)
    }

    @Test func inspectionWaitsForTheNameAndGivesUpAtTheCap() {
        #expect(FlowRules.inspect(Fixtures.helloForMobileYouTube.prefix(50), port: 443, rules: rules, now: now) == .more)
        // The same cut-off bytes, padded past the cap: still no name, and no point waiting.
        var padded = Data([0x16, 0x03, 0x01, 0xff, 0xff])
        padded += Data(count: FlowRules.maxInspectedBytes)
        #expect(FlowRules.inspect(padded, port: 443, rules: rules, now: now) == .allow)
    }

    @Test func inspectionOfLapsedRulesAllows() {
        #expect(FlowRules.inspect(Fixtures.helloForMobileYouTube, port: 443, rules: rules, now: at(8, 22, 0)) == .allow)
    }
}

/// Real ClientHellos, written by OpenSSL 3.6 through Python's `ssl` module with no network at
/// all (`MemoryBIO`), so the parser is tested against what a client actually sends rather than
/// a hand-built approximation. TLS 1.3 offers with X25519MLKEM768 key shares, so they are as
/// large as a hello gets.
private enum Fixtures {
    static let helloForMobileYouTube = hex("""
    16030105e9010005e503039f495947436ecfea4c0ccfd8ca373d3f888de975beae1ad01528f4388a2722b620cf5da5ea02acd3d28da3357024e6aba9a15e7fc9b9cb3f0cc74bb7dd9dbb71e40022130213031301c02cc030c02bc02fcca9cca8c024c028c023c027009f009e006b00670100057aff0100010000000012001000000d6d2e796f75747562652e636f6d000b00020100000a0012001011ec001d0017001e0018001901000101002300000016000000170000000d0036003409050906090404030503060308070808081a081b081c0809080a080b080408050806040105010601030303010302040205020602002b00050403040303002d00020101003304ea04e811ec04c0c3f3c4f478281e652764847adfd25341f37baa7503731a39c8cab224bc07e8f6043dc2aac6eb3a1a21b0c5046f487b72e1acbe2ac15fe04603c235cc51119d4e2288c773c63ea973ea840ac865828d92c74ad850eca23fe18961e361b184dc9395c8ba3d5ba75085014ad027cc07c5f60bc121eabebecacfba938a683279a95b70d49c1e1adcc45ef27364e7069d78c52d882bb9ab10ba8b44d955b8b9f01c8275bff7a6ca04010ab4919ce497586201132543c52709adbac1867cf4126f183f63409dae490af99509b371a5d97ba18dd82d43bac51e74703f2ccc19ec90f8f0289c8985de367e5a5c8f5636a80b9484f190c84301492f84603ebc3c67e66da279b68b31739364773de03f59a711472b61c5465f4e349ad72b90f0b49fe1eb5731a01f242ac9259362ffa03611511e6f455fd4fb4f3599484312c8020ccb272ab8a4e1a0340883bd872c7e2382cb1c2cb9c20e6ad087a774b630628399434427f50df031c143b804d906a298499206c84bd3749c01c07fe4e6c3efc636f5246e9c3557b610024228a492a82442b6668949112455ad14732826519092c4cc38147cb2cb57453cb8dc23a404f00b3dcc8705d94c0f0c37584a9550d2a277b5b79db96dfe6591e3972dc826abc68b907852ccddd2a76501c11504ac08a67dbd043af5301d0a171971b1529a53ad55921c392a3d262c45940a8ecd91c04720589c6ab15e51ad3ea00338544c59f7b50ef19037f1c9354a4ce8e609190081081279f4c9bff65412764933664a35187887f10c388f830efee31306a9474957136d4323d77a2eb2156513087b219b88f773782747667f9a6f9a9a2590ac884dfb2a5233a293e383c146a9a148a3e77388bc7a9268c2caaec513ed485ad4c79a6d609004766aad00970c46555a63ad1d9c6121805884fa108279bc25b94859507589c2ce01f704e342644d1c31c5436632a947dff00bbca3b64264b9593a4df727c37c729d4d1ba6937caf7ff4181803b839812971089fbdb471787685e4273ca948aae263b5c8638dc96108c47c30eff20420e240ba24ab60d8749649c49b3c699c3cc69989a039ec5705808c48178cc138227eb41b3c0319579b88be2344c4a40dfe78cbb58711b42307c6f05b86586c7ad09cd5a8909c777909f45e62903ac2e69692f00b88446d90c8936fc95edce3929077b7cc43a05f28367ae16093e45f9a3a8e0668137eb678807c4d4828b0d3da97dfa44691500c89cb707b6549dab1b6ee3c5db1ab40a7dc4976f0c9ec7b87f0f75961708f6e8a5842e94ce32b975966baa439a731612aabf044933850d2385018732e83213e01d12b8f636b208b1b298265dda59fa187b5372887fb9267603427887b9031b051b8731d550196fca2545571a4beb9029cc169b4f16b49a736fc919858393361b3b56f3c0605432c558c887b3cba8895c3298183bd30aade00048e88bfe258928fc63dd5171b130c5726f225a0aa5c72dc550f60b4b2c2b5dd479bb344039e13c5f1d617442ba361d4cdb1c8004571354a2c84f2a677ba6891f43c1c47d28a89268d971a171b6973507205e3c271f9d6b633230cc46015afc6836e9734eeb5929e39a8681c61dd733de3b217a1f4c2d0a1afa5f1d06aaf4d9df9e3cc9cfdff4a4231d7c78b483a490e9f56c0414b1468f6801db4b32377ce29bcb04a7b6ccde3c1a757c431ecf67b86445f0c001d0020610639a31ccba0f09ce4080bd2a2898f20e40de742cac8fee9da0dfa87edf95f
    """)

    static let helloWithoutName = hex("""
    16030105d3010005cf03030fdcba444af683e9be5fcdfef5529e1bd687ce5dc2e90eb5e31791b302fd208420f080d3b0d3d5da5e1a3e18193568c6452c885da5ae2147fbebc1a127abdb11750022130213031301c02cc030c02bc02fcca9cca8c024c028c023c027009f009e006b006701000564ff01000100000b00020100000a0012001011ec001d0017001e0018001901000101002300000016000000170000000d0036003409050906090404030503060308070808081a081b081c0809080a080b080408050806040105010601030303010302040205020602002b00050403040303002d00020101003304ea04e811ec04c0c556b9fdd4887cc47a8ef60216699329d7cb0065057c11bb6bfa6fe37b1b084b1d02c2682fa32bf8352efdf97a349807354c341145862a9658c9cba6241639bad23e2441be31ca67c70c0aef420720e3c30d868e3c2c12b07952cf339893e96c6cc2a4102590baa7962136a65c089a6af26ec70772877140465a81d63318491559c34a3ac926afac0125609cc645153d33797294ccce0e7330c5a0076bc3c0b15074847b915543b9fe6012007a8d680cb09bbc0a95a58f9b167eb855a05b397af6b9282f287ef680688329853d0a178dc9673bbc99f2e7731f8831fdb273bde95810f0c52131b4d570b276a50157624fe0e4cc2667517b121cc65768561c11893057341976a8b94a90342afa1a0c1be0384b93090d22bd50764d4b225e84863de6dc9377d72e1a77bd2ce40862db788143133ecc44936078ea299358b47bbf6850df779c8b88656301a7b1787ec8613817512cfce726151a9fa8c41d4b7741402a7642852358fb3d45454768cbc52cb0396ee047fce659794944f2ea07795725e3f682f62079df64b868d873a7825a9adb39e8153fdb9196895767325c5b7cd23b86c95d9cf81829796313d017ebbc6015c1977f318f1f5aceea9a901d9119cd5b79652870d33a55888b2705046d8bb261d1f6aa670986e1b91058a39641f508f0033490ea9902d8780f632e6c1545053b1ceaebcaa4991147486a51196cdfe3c5197453e4553afd2551286a7e6bd989d22137bf418b59ec9e966279c146bc7b3c0341a924baba6f3308657d93b2cfc95fbaa447c8d23f9cd1964a5a137c8486cc1bc4ac46cb4bdb357da7ba6b3497de6ab16d394ab02478186129bcb7b7b1533a62232e871b29ccc7435e181623496dd25c8fd871448cf4c99f70a2976b56069b4b4525904229b6cb09990825678a95a4bc3508304a9769c71872892460dc2aac180c87a587fde6a13ff9cfcb651d8de7474cd15c1824a6c8999fc2e5951f73a79d3a2f8a9a742e13681d219a08b39e661b44113c628e506fcd5c8cece940ab4c1b73fb18ffdc7351521085f2bc1e02040458b951a36f40babfa0cb1c11e360877aa33af08a7a09cd9b5527a9b9976b2b5bdb5621172aa597b87b9003806950ad09b62c80f941e0ac85762c9eef6caa852461e1130b0495bd569188c88b8e1f1697e8e31b8a4a69936a883a757e205c9bf6c7ac3b1450b68933b2e68177e51f6659933a76742300bab536232670047d3a2d51b164697bc542f460ba271dc14a3bd877099549704441769370af0c742e44e93bfdc36760913fe3c8a5f2e2ca9219459c5a4c13d58ba84b1a9d54b1a233ae30e85abe0720331837a298cc4ed562f5d04d5876bcfceb540990c258a84b6a05408c3709e44011332a63b4b57e198410736b0bdba6a0a215ae0d482795c90f384c3990084230a458fc6682368a686986b183a61cd5367ba1ecb93cf225b653887bca04aeb39f0465287e337496d00bc7841409d0134b645ea5a8bef26bb2343ba6f75b8e293061b3d32aa9b6c147a7291e249f3bacac0cea6c2f5cb64e8cb35356bfbbcb2fe1731cdfe99d88795e244708ed5b0a523719715cb67f2440ab974ed3c9b56875bfe1dc0e6f995ab83b7b1ef9161dfa4f9911c5e5ba887c4876d3ecfe8fdb7df1912075f69c52fd7e06294f653fabdb3c16edd748cc99345fb5967a86f29f8f588ce7a6ce46d2bca4043f001d0020c29c84a60e7d275d130f46e39533ff3509baffe699f6c54939a8670eb380cb26
    """)

    static let helloForLongName = hex("""
    16030106110100060d0303d88f223c6ea2e2a6758ed56ad2ee45bf04b04d61f1699b8862a64bba69aaddae20d6a28abfb90d44749f8fabf3e8ab385af46bd31c6825ae5facaa8d5071dc254b0022130213031301c02cc030c02bc02fcca9cca8c024c028c023c027009f009e006b0067010005a2ff010001000000003a0038000035612d7261746865722d6c6f6e672d737562646f6d61696e2d6e616d652e6173736574732e6578616d706c652d63646e2e636f2e756b000b00020100000a0012001011ec001d0017001e0018001901000101002300000016000000170000000d0036003409050906090404030503060308070808081a081b081c0809080a080b080408050806040105010601030303010302040205020602002b00050403040303002d00020101003304ea04e811ec04c0e11969f32a4c94d01121018c1ca1ad54301e0698abd8f9cc69ca4560b137cef00575151f4517785b826bb0c2cf786501d7120a945c649435803ea7c3c60757c16427c09c9dc1e7707ff954b3966200a49f0647b059d23aad243ff4e1497451cee83867baecbd1fc21c04061cdb0980b7f2412f9393dea9857db5843f296c8d54cdd03506856083b824855eba70d11ab85e3a2b16b3609bf07229eb0211d23f1818c7adc7c4ff640f10b71472b3c7faa4451a004328b0ca71366798dc1e3687ba0dba9d9ce35482916ee7f2b38bb0b1a6ea8c0e25cfe112170801267cbc9600e24ad2c2a0306a84f9441cbc78639a35478398475a83329a8928853496f8c38e16303d90d2a9c5c85c759639e2a44145e77a5e8c9100643643e78f4991666403cb8433448355add1dbaa8c078ba9585273e070596b3164c48644c975e0998bc549b0c4f6591a17899d776b6b0ac0700b17ed98074106bbdd0084f9ab8f766c5aa8545404fc56445261f5418c4be1195b8a00ebd9296d4a1a36b594b0e9157a431e499a4107e16b2e5c62ac22ae40f99e653021a0581fdb484be26b79b9220b5aeb2843fac6221679206a957c962022f7973ec28f02629c7e161f98687adab1bbb241be8b49102014bf9edc344d668365a21f7981ae7cbb8e5f7a83e68210443a80c3499eb88b51f19b3cf5b6439bc471640467030044880a9481f27ff3a1c2d1589318585368099307d963c84a215d36668f624da7bccc9423b45eb86cb3891aaae53b4868722c2c70f3b463fdf9a89b43903be7767343c019e96b766b38a128773cb277b42063fd0120cd7b93d615beb75859ee8133deea68d83b877ed69fe8a8bfacd8b4c4c1ca16d67b07269d8498480d0a7f162b8efce9931133708e358addf6bc7fe2240db60cabdc41e640acf3a363f0c213dbe4b3294ac109d412da67213c79b26b96aea1f3597e689c52a83b4b528e3b46087123b2be4364304ca1b3220bd4739af4bb13af79a2b046047ba252804682c6c67ac9aa86a6db7db73c8ba215a87ee21d5155a7db851f68375f53e5b42b99cb82747bc741077d2c47e9c7459edc810042489edbbb47fc8114c749a1d0c10cc70b10c7be04fb8872ac1e003c0877d10f98704d1cfa32db725e8a05a7e022c2d378c8e38083a73a7c182b7d4c33ccc14379b110bd92f9cdd2d2300e82c4e954885d3a461e5ab9bb15695063cf3d1828a217b8f507d0b604d0c730928d3a0564f39f4cf078bd00123fa18647360a0a0c204e1039f036c49f672188c795160c8414368fad3552ecd244acc1ca7bf58cdf26249f83799c31c42f7a9daafb9c56d1788e70b0efb4b5723948aa2b1361f9a7fd471c46daa54e791236a91e8bf70cacb2502f76a0ed9266931120fce25a9068afeae13b1612a016688014c429a1e56599430fc0a341c2403e3ad55b6eb43c2d584cafcb8b76b835d2f930fff61b5f91bb4473093ac191b3953ea7f917a352b282e68a21080d7aaa898e25741e730818d2157a4ab0e82831f09cbff0914871e405d589684683380df47674e646e66b069e37278cb9a2360937953289576ab8cd230f243482b3a542e390a034f67d480575ce5611f767c334e6bffdc61069e873212b7d497bf09bef04794be4c3fa4e2e053513148bd10b046a6a7f1e5e566dab0bbcd35f4af596cafa761f226daa94a069755dddec479ad9a3e604822a001d002000f5e6e9161210950156cd1a6b10244fbc2f0676b029aafd78201d8ef0abb365
    """)

    private static func hex(_ text: String) -> Data {
        let digits = Array(text.filter { !$0.isWhitespace })
        return Data(stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0...$0 + 1]), radix: 16) ?? 0 })
    }
}
