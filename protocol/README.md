# Protocol: the Furlough contract

This directory writes Furlough down in a form that is not Swift. Sections 1 to 10 cover what
crosses between a person's devices. Section 11 covers what one device decides on its own.
Section 12 covers the lookup tables those decisions read. A second implementation, such as an
Android or Windows build, can be written against these pages and checked against 90 test
vectors generated from the Swift.

The link is four kinds of JSON value in a key-value store. The engine is a handful of pure
functions over a rule. This directory gives the shape of both. It holds no port and no relay,
and it has no transport code. Nothing in an app compiles from it.

It describes what the code does today, not what it might become. Where a rule may change,
[Not decided](#not-decided) says so, and the numbered section still states what runs. If a
sentence here disagrees with a vector, the vector is right, because the test keeps the vectors
equal to the code.

| Path | What it holds |
| --- | --- |
| `README.md` | this file, the contract in words |
| `schema/` | JSON Schema (draft 2020-12): `anchor-record.json`, `linked-device.json`, `revocation.json` and `shared-addition.json` for the four values that cross, and `config-export.json` for the setup file |
| `fixtures/merge/`, `mac-drop/`, `roster/`, `additions/` | the link: 42 vectors |
| `fixtures/policy/` | the rules engine: 48 vectors |
| `tables/` | the identity and advice tables, four JSON files |

The Swift these pages come from is in `Shared/Core/`. For the link it is `AnchorSync.swift`,
`DeviceLink.swift`, `SharedAdditions.swift`, `LinkFlow.swift` and `ConfigExport.swift`. For the
engine it is `Policy.swift`, `Models.swift`, `ActivityLimit.swift` and `Utility.swift` (the
delay arithmetic), with `Clock.swift` for the time zone hold. The tables come from
`Companions.swift`, `AppUtility.swift` and `RuleSuggestion.swift`.
`Tests/Core/ProtocolFixturesTests.swift` runs every fixture against the real code, checks every
schema against a real encode, and checks the dumped tables against the Swift tables. The
commands are under [Using the fixtures](#using-the-fixtures).

## 1. What crosses, and what never does

Three kinds of thing cross between devices: the anchor's state, the roster of devices, and the
name of something a person added. That is the whole list.

What never crosses, and cannot be made to:

- Screen Time tokens. An `ApplicationToken`, `WebDomainToken` or `ActivityCategoryToken` is an
  opaque blob that Apple scopes to one device and one install of one app. It means nothing off
  the phone that minted it. A phone can never send "this app". It can only send what it has
  learned the app is called.
- Rules, as such. A rule travels only as a passenger on an addition (the sender's `Rule` for
  the thing it just added), and it lands only where the receiver's row has none. There is no
  rule sync, no shared list of targets, and no way for one device to edit another's rules.
- The anchor's list. `AnchorProfile.kinds` is tokens on the phone and bundle identifiers on the
  Mac, so each device keeps its own. The names of things on it cross as additions made to the
  anchor's half (§7, §8), and each receiver decides what goes on its own list.
- The setup file. `ConfigExport` (§9) is a file a person hands over by hand. It never goes
  through the link. It is documented here because a port has to read one.

Apart from the anchor record, which is one slot ordered by its sequence (§2), everything that
crosses is state that a device writes about itself, under its own key. Nothing else is shared,
so there is nothing else for two devices to fight over.

### The gate

**A device that is not enrolled reads nothing and writes nothing.** Enrollment is opt-in, per
device, and it gates everything, the Anchor included. `AnchorSync.pull` returns at once when
this device is off the link. The record is never read, which differs from reading it and then
refusing it. `SharedAdditions.pending` returns an empty list.

A record written by a device that is not on the roster is refused even when this device is
enrolled: `pull` accepts a record only when `remote.writer == deviceID` or
`roster.isLinked(remote.writer)`. A record left behind by a device that has since left is a
lock with no owner.

Grandfathering is the one case that looks like an exception to the gate and is not one. It is
how an install that predates the roster answers the enrollment question without being asked.
`DeviceLink.grandfathers(lastHeard:phoneSeen:)` is `lastHeard != nil || phoneSeen`. A device
that has ever read the other device's write enrolls itself on first launch. A device that has
only ever heard itself, or nothing, starts off the link and is shown the guide. The question is
settled once and latched under `furlough.link.decided`.

## 2. The four keys

Every value is JSON, stored as `Data` under a string key in one flat key-value namespace. There
are no nested containers and no lists to keep in step. The roster and the rings are found by
listing keys by prefix.

| Key | Value | Written by | Removed |
| --- | --- | --- | --- |
| `furlough.anchor.v1` | one `AnchorRecord` | whichever device last changed the anchor | never in normal use; debug reset only |
| `furlough.device.<id>` | one `LinkedDevice` | that device, about itself | by that device on leaving, or on obeying a revocation |
| `furlough.revoke.<id>` | one `Revocation` | any linked device, about another | by `<id>` itself when it re-enrolls |
| `furlough.adds.<id>` | array of `SharedAddition`, at most 20 | that device, about what it added | with the device's entry, on leaving or revocation |

`<id>` is the device's own identifier: a UUID string made once per install and kept in the App
Group, so every process on the device signs the same way (`AnchorSync.deviceID`). It is the
same string that appears as `AnchorRecord.writer`, `LinkedDevice.id` and `SharedAddition.origin`.

### Lifetimes

- The anchor record is a single slot, overwritten by every write. It has no history. The
  `sequence` orders writes, not the store.
- A device entry lives as long as the device is on the link. It is rewritten in full on every
  enrollment and whenever the device sends an addition, so `lastSeen` is the time of the last
  of those. `enrolledAt` is carried over from the existing entry on a rewrite, so a refresh
  never spends a revocation that has not been read yet.
- A revocation outlives the device entry it kills. It stops applying once its `at` is older
  than the entry's `enrolledAt`, because the device was taken off and came back, and that is
  called spent. A spent revocation stays in the store. It is deleted only when the named device
  re-enrolls (`enroll` removes `furlough.revoke.<own id>`).
- A ring is a rolling window of the last 20 additions from one device. It is not a queue:
  nothing consumes from it. Receivers track their own position (§7).

### Ordering

One monotonic counter is shared between devices: `AnchorRecord.sequence`. It is monotonic by
construction, and the devices never have to agree on it. Every local change to the anchor (a
drop, a scheduled drop that lengthens a hold, a tag release) sets the sequence one past the
profile's current value, and a merge adopts the remote's value, so each write is one past
anything the writer has seen. A record whose sequence is not strictly greater than the local
one changes nothing.

Addition sequences are per sender (`furlough.link.sequence`, one higher on every send). They
are never compared across senders. A receiver keeps one watermark per source.

## 3. The values, field by field

### Encoding

Every value that crosses is encoded by `AnchorCloud`:

- `JSONEncoder` with `dateEncodingStrategy = .iso8601`, decoded with the matching
  `dateDecodingStrategy`. Every date is an ISO-8601 string such as `"2026-09-08T12:00:00Z"`.
  Foundation's `.iso8601` writes UTC with a `Z` and no fractional seconds, and reads the same.
- There is no key sorting and no pretty-printing. These values are blobs that no person
  reads. (`ConfigExport` is a file a person may read, and it is pretty-printed, see §9.)
- A `UUID` is its uppercase string: `"6BA7B810-9DAD-11D1-80B4-00C04FD430C8"`.
- Absent optionals are omitted, not written as `null`. A reader must treat a missing key and a
  null the same way.
- A value that will not decode is skipped, not fatal. `DeviceLink.roster()` drops a device
  whose entry it cannot read (for example, one written by a newer build with a platform this
  build does not know) instead of failing the whole read. A ring or an anchor record that will
  not decode reads as absent. A port must do the same, and so must never assume the enums below
  are closed.

### `AnchorRecord` in `furlough.anchor.v1`

What one device says about the anchor, as the other receives it. It holds the anchor's state
and nothing else.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `sequence` | integer | yes | Monotonic across all devices. Every write is one past anything either has seen. |
| `isAnchored` | boolean | yes | Whether the writer's anchor is down. |
| `anchoredAt` | date | no | When it went down. |
| `until` | date | no | When a timed hold ends. Absent means only the tag lifts it. |
| `writer` | string | yes | The writing device's id. |
| `platform` | `"phone"`, `"pad"` or `"mac"` | yes | What wrote it. |
| `origin` | `"drop"`, `"tagScan"` or `"lift"` | yes | How the write came about. |
| `writtenAt` | date | yes | The writer's Furlough time at the write. |

`platform` has three cases because an iPad runs the phone build and has no tag reader. It can
be anchored and can never release, which is the Mac's position. Core has no UIKit, so the app
notes the idiom at launch (`AnchorSync.notePlatform`) and every process reads the note.

The `origin` values:

- `drop` is a drop by hand, from a widget or Control Center, or by the schedule.
- `tagScan` is the one release: a paired tag read by a phone.
- `lift` is a timed anchor's `until` passing. It is informational. The receiver computes the
  same expiry from the `until` it already holds, and `merge` refuses a `lift` as a release.

### `LinkedDevice` in `furlough.device.<id>`

What one device says about itself to the others.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | string | yes | The device id. Equals the `<id>` in the key. |
| `name` | string | yes | What the person called it. Trimmed. Falls back to the platform's word. |
| `platform` | `"phone"`, `"pad"` or `"mac"` | yes | Same enum as the record. |
| `enrolledAt` | date | yes | When it joined. A revocation older than this is spent. |
| `lastSeen` | date | yes | When it last enrolled or sent an addition. |
| `canRelease` | boolean | yes | Whether a tag can be read on it. |

`name` is typed by the person on a phone, because iOS stopped telling third-party apps the
device's name in iOS 16. The Mac offers `Host.localizedName`. An empty or whitespace-only name
becomes `"iPhone"`, `"iPad"` or `"Mac"` (`LinkedDevice.defaultName(for:)`).

`canRelease` is written as `platform == .phone`. It is a fact about the hardware that no setting
changes, because only an iPhone has a reader. The roster carries it and `merge` does not yet
read it (see [Not decided](#not-decided)).

### `Revocation` in `furlough.revoke.<id>`

One device taking another off the link, written under the revoked device's id so that device
finds it on its next read.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `by` | string | yes | The revoking device's id. |
| `at` | date | yes | When it was written. |

Any linked device may write one. The named device un-enrolls itself on its next read
(`obeyRevocation`, called from `AnchorSync.pull`, so it lands in whichever process reads
first). Every other device already leaves it out of `Roster.linked`, so a revocation takes
effect at once for everyone else and on the next read for the revoked device.

### `SharedAddition`, an element of `furlough.adds.<id>`

One thing a linked device added, as the others receive it: what it is called and every
identifier and host it goes by. It is never a token.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | uuid | yes | The sender's target id. A second write about the same thing replaces the first in the ring. For something that only the anchor's list holds, there is no target, so the id is derived from the normalized title. |
| `sequence` | integer | yes | One higher on every write from this sender. What the receiver's watermark counts. |
| `title` | string | yes | What to call it: `"YouTube"`, or the host when nothing better is known. |
| `isApp` | boolean | yes | Whether the sender's face was an app. |
| `bundleIDs` | array of string | yes | Lowercased bundle identifiers it is known by, on either platform. May be empty. |
| `hosts` | array of string | yes | The hosts the sender actually blocks for it. May be empty. |
| `rule` | `Rule` | no | The sender's rule, if it had one yet. |
| `half` | `"rules"` or `"anchor"` | yes | Where it was added. |
| `origin` | string | yes | The sending device's id. Equals the `<id>` in the ring's key. |
| `platform` | `"phone"`, `"pad"` or `"mac"` | yes | What the sender was. |
| `addedAt` | date | yes | When it was sent. Receivers order by this. |

`Rule`, when present, is the store's own rule shape:

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `windows` | array of `TimeWindow` | no (absent means none) | Allowed spans. No windows means open all day up to the budget. |
| `dailyBudgetMinutes` | integer | yes | Minutes a day in total. |
| `budgetByWeekday` | array of 7 integers | no | Sunday first. Anything but exactly seven entries decodes as absent, because the safe reading of a damaged field is the rule's one budget and never a day with no limit. |

`TimeWindow`:

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `startMinute` | integer 0 to 1440 | yes | Minutes from midnight. |
| `endMinute` | integer 0 to 1440 | yes | Exclusive. 1440 is midnight. |
| `days` | integer 0 to 127 | no (absent means 127) | Bit set. Bit 0 is Sunday, so the bits line up with Calendar's weekday numbers 1 to 7. |

A stored span never crosses midnight. An evening that runs late is an evening window plus an
early-morning window on the next day, and the second window's `days` are shifted one day on.

### What a sender can and cannot describe

`SharedAdditions.describe` returns nothing at all for some targets, and a port that sends must
know which:

- A category never travels. There is no name a receiver could act on.
- A picked app or website (an iOS token) travels only once the phone has learned its name,
  from the shield or from Screen Time's own tables. A picked website also needs a name that
  reads as a host. Until then `describe` returns nil and the target sits in
  `LinkFlow.awaiting`. On a phone the addition may follow the add by hours.
- A typed host and a Mac app name themselves and travel at once.

Where the companion table (`tables/companions.json`) knows the thing, the addition picks up the
table's bundle identifiers beside whatever the sender had. An app also takes the table's title.
So an app added as YouTube goes out as `"YouTube"` with `com.google.ios.youtube` beside it. A
typed host goes out under its own name and still carries the table's bundle identifiers. The
table's hosts are not added on the sending side. The receiver adds them (§8).

## 4. Merging the anchor

`AnchorSync.merge(local:remote:now:)` is pure and returns a profile and a note. `now` is
Furlough's own time, never the wall clock.

The branches, in order. The first that applies wins:

1. Stale. `remote.sequence <= local.sequence` changes nothing at all, not even the sequence.
   The note is `stale record (N is not past M)`.

   Otherwise the local sequence is set to the remote's before anything else is decided, so
   every branch below moves the sequence on even when it changes nothing else.

2. A release (`remote.isAnchored == false`):
   - It is accepted only when `origin == "tagScan"` and `platform == "phone"`. Anything else
     gets `refused a release that was not a phone's tag scan`. That covers a Mac writer, an
     iPad writer, an `origin` of `lift`, and an `origin` of `drop` with `isAnchored` false.
   - If it is accepted but nothing is holding here (`!local.isHolding(at: now)`), the note is
     `released by the phone; already up here`.
   - If it is accepted and something is holding, `isAnchored` becomes false and `anchoredAt`
     and `until` are cleared. The note is `released by the phone's tag`.

3. A drop already over by this clock. `remote.until != nil && remote.until <= now` changes
   nothing else. The note is `a drop already over by this clock`. This is why a `lift` needs no
   special handling: the receiver reaches the same conclusion from the `until` it holds.

4. Something is already holding here. The tighter of the two `until` values wins
   (`Policy.tighterUntil`: an absent `until` is tighter than any date, because it means only
   the tag lifts it, and between two dates the later one wins). If the local value is the
   winner, the note is `already anchored here`. Otherwise the hold is lengthened, with the
   note `hold lengthened by the other device`.

5. Nothing is holding here. `isAnchored` becomes true, `anchoredAt` comes from the record or
   from `now` when it has none, and `until` comes from the record. The note is
   `anchored by the other device`.

A remote `until` is always judged by this device's clock. A drop that is already over here does
not drop here, and a drop over an anchor that is already down can only lengthen the hold.

`AnchorSync.pull` wraps this with the gate (§1). It first obeys any revocation of this device
(§6). It then has two side effects worth porting. `phoneSeen` latches the first time a
`phone`-platform record is read. `lastHeard` is stamped for any record this device did not
write, before the merge and whatever the record turns out to say. A record that changes nothing
here still proves the two devices are talking, and that is the question the link status
answers. Hearing yourself is evidence of nothing.

Vectors: `fixtures/merge/`.

## 5. The Mac's drop

`AnchorSync.macDrop(_:now:hasKey:cloudAvailable:)`. The Mac has no tag, so it takes no `until`
and does not ask `canAnchor`. It first lifts an expired anchor, and then it refuses in this
order:

1. `noList`: `!config.anchor.hasSomethingToHold`. Nothing is on the list and the scope is not
   everything-except.
2. `noCloud`: the store is unreachable.
3. `noPhone`: no device on the roster besides this Mac can release.
4. `alreadyAnchored`: the anchor is already down here.

Otherwise it drops: `isAnchored` true, `anchoredAt` set to `now`, `until` cleared, and
`sequence` plus 1.

The order is load-bearing. `noCloud` is checked before `noPhone` because it makes the other
unanswerable. What the roster says was read from an account this Mac may no longer be signed in
to, so trusting the roster alone would let through exactly the lock with no key that the guard
exists to stop. The two checks are one guard in two forms: a Mac must never hold an anchor
whose key cannot reach it. They run in the order in which they can be fixed.

`hasKey` is `Roster.hasKey(besides:)`: some device other than this one, on the link, with
`canRelease`. It replaced a latch that was set the first time a phone was ever heard from and
stayed true after that phone left.

`DropRefusal` has two more cases, `nothingToAnchor` and `tooSoon`. They belong to `Policy.drop`,
the phone's drop, which does take an `until`. `macDrop` cannot return either.

Vectors: `fixtures/mac-drop/`.

## 6. The roster, and leaving

`Roster` is `devices: [LinkedDevice]` and `revoked: [deviceID: Revocation]`, read from whatever
hands it the entries.

- `linked` is the devices on the link: written, and not revoked since they enrolled. A
  revocation applies when `revocation.at >= device.enrolledAt` and is spent when
  `revocation.at < device.enrolledAt`. The list is sorted by `enrolledAt`, oldest first.
- `isLinked(id)`, `device(id)` and `others(than:)` all read `linked`.
- `hasKey(besides: id)` is true when some device other than `id` in `linked` has `canRelease`.
- `othersDescription(than: id)` gives "your other devices" for none, "your iPhone" for one,
  "your Mac and iPad" for two, and a comma list with a final "and" beyond that.

Leaving: `DeviceLink.leaveRefusal(anchorHoldsHere:anchorHoldsOnLink:)` refuses with `.anchored`
when either is true, and otherwise permits. Both leaving and revoking another device take the
same refusal, because an anchor that holds anywhere makes every device a party to it. Taking a
device off while it holds would either leave that device locked with no key or release it, and
both are what the Anchor exists to make impossible.

The message: *"The anchor is down. Scan your tag to release it, and then any device can be
taken off the link."*

`anchorHoldsOnLink` is `DeviceLink.recordHolds(record, now:)`. It is true when the shared record
is anchored and either has no `until` or has one still in the future by this device's clock.

Leaving is otherwise instant. With no anchor down, the link holds nothing that leaving would
let go of. Leaving removes this device's own entry and its own ring, and sets enrollment false.

Vectors: `fixtures/roster/`.

## 7. The ring, the watermark, the declined set

Each device publishes to a ring of its own, and every other device keeps its own position in
each ring. There is no shared list, so there is nothing to fight over, and a device that was
off for a week reads the rings and catches up.

### Deciding what to send

`LinkFlow` decides when a device writes to its ring. Nothing is sent unless the device is
enrolled and its `sendAdditions` setting (§9) is not `never`.

- Something added to the rules half is noted as awaiting, by target id. `LinkFlow.outgoing`
  then asks whether it can be described yet (§3). If not, it keeps waiting. If so, it is sent
  under `always` or when that target was sent before, and otherwise it is offered to the
  person under `ask`. A target the person declined is not offered again.
- Sending stamps the next sequence from this device's own counter, sets `addedAt` to now,
  writes the ring (below), and remembers the target id as sent. The target's first rule, added
  later, goes out again without asking. It carries the same id, so it replaces the earlier
  entry. A resend keeps `half` at `anchor` when that name was sent to the anchor's half before.
- The anchor's half keeps no awaiting ledger. Each time the device settles its sends, it walks
  the anchor's list and describes what it can name, skipping names already sent or declined
  (compared by normalized title). Under everything-except, or with an empty list, nothing is
  sent, because there the list is what stays open and sending it would tell the other devices
  to block exactly what this one keeps reachable. Under `always` these go out. Otherwise they
  are offered.

### Writing

`SharedAdditions.appended(ring, addition)`:

1. Drop any existing entry with the same `id`. A second write about the same thing, such as its
   first rule landing, replaces the first write and does not sit beside it.
2. Append.
3. Sort by `sequence`, ascending.
4. Keep the last 20. That is enough to cover a week away and small enough that the whole store
   stays far under the store's megabyte.

### Reading

`SharedAdditions.unseen(rings:watermarks:declined:thisDevice:roster:)` returns, oldest `addedAt`
first, every addition such that:

- its source is not this device, and
- its source is in `roster.linked`, and
- `sequence > watermarks[source] ?? 0`, and
- its `id` is not in `declined`.

The watermark is per source and moves only forward: `markSeen` sets
`watermarks[addition.origin] = max(existing, addition.sequence)`. It moves whether or not the
addition landed. Landed, declined and nothing-to-do all mark it seen.

The declined set is kept apart from the watermark, and the separation is the point. An addition
that is still waiting for an answer under Ask is below the watermark and not declined, which is
what makes it show again on the next read. Declining sets both.

Vectors: `fixtures/additions/`.

## 8. What a receiver does with an addition

`SharedAdditions.landing(for:in:installed:companion:now:)` decides and `land` performs.
`landing` writes nothing, so under Ask a person can be shown exactly what would happen. It takes
a clock because one of the four things it decides, the anchor's list, is read against the
anchor's own state at that instant.

Finding an existing row, in this order:

1. By host: any of the addition's hosts already covered by a row. Both platforms answer this
   exactly.
2. By bundle identifier, on the Mac only.
3. By learned name: the addition's title against a row's `systemName`, normalized (trimmed and
   lowercased), or a row whose name is in the companion table with one of the addition's
   bundle identifiers.

**The app half.** This applies only when `isApp` is true and the row that was found does not
already cover an app:

- On the Mac, the app is the first of the addition's bundle identifiers that is installed here
  and is not already a row. `installed` is a map of normalized bundle identifier to name,
  walked from the Applications folders, and only when something is actually waiting, because
  that walk is not something to run on every poll. If nothing is installed there is no app
  half, and the hosts still land.
- On the phone, `appNeedsPicker` is set. Nothing there can mint a token, so the site half lands
  and the app half becomes a nudge towards Apple's picker.

**The hosts.** These are the sender's hosts plus, when this device's `companionSite` is
`always`, the companion table's hosts for the addition, minus every host already covered by a
row. So a Mac with no YouTube app installed still lands `youtube.com`.

**The rule.** The addition's rule lands only where the found row has none. A rule of your own is
never overwritten by a device you are not holding.

**The anchor's list (`anchors`).** This is set when the addition was made to the anchor's half
and this anchor can take one: it is not holding at `now`, since nothing changes the list under a
lock, and its scope is not everything-except, where the list is what stays open and so never
grows by an addition. Given that, it is set whenever something new arrives (an app or a host).
Where nothing new arrives, it is set only when the row that already covers the addition is not
on the list. It is a field of its own because it is the one thing left to do when there is
nothing to block. A Mac that already blocks YouTube still needs to hear "hold it here too", and
dropping that would let the arrival go missing.

`isNothing` is true when there is no app to add, no host to add, no rule to give, no change to
the anchor's list, and no app owed. The caller then marks the addition seen and moves on
without asking anybody anything. An app is owed (`owesAnchoredApp`) when a phone hears that an
app was anchored elsewhere: `appNeedsPicker` with `half` set to `anchor`. There is nothing to
block by name, but Screen Time's tables may yet match the app to a token, and otherwise the
offer is how a person learns that the picker is the way in. So the offer is shown and not
swallowed.

**`land` is a tightening in every part of it.** More is blocked than a moment ago, so it lands
at once with no delay, and a rule it brings gets the undo window exactly as a rule saved by hand
does (`RuleUndo(rule: nil, savedAt: now)`). Where `anchors` was set, the rows it touched go onto
the anchor's list. That step is re-checked against the clock and not trusted from the landing,
because under Ask time passes between the offer and the answer, and the anchor may have dropped
meanwhile. A port that decides once and performs later must re-check the same way.

### The shape differs by platform, on purpose

| | Phone | Mac |
| --- | --- | --- |
| App and its site | one row. Hosts are linked onto the row (`Target.also`) | a row each. The app is one row and each host is another |
| App the receiver lacks | cannot be added; offered through Apple's picker | added when installed, skipped when not |
| Rule | given to the row that has none | given to each row it creates that has none |

The phone has held an app and its site as one row since 2026-09-08. The Mac has never drawn a
linked half, and there each host is a row of its own, exactly as its companion sheet adds them.
A linked half that the Mac's editor could not show would be a block with no handle. A port must
pick one of these two shapes and say which. The choice is a fact about that platform's editor
and not about the contract.

Vectors: `fixtures/additions/`, the `landing-` files.

## 9. The three settings

`Config.link` is a `LinkPreferences`. It is kept per device, decoded with `decodeIfPresent`,
and never exported in the setup file. Each setting is `always`, `ask` or `never`. There are
three answers and never a fourth, so a person learns the scale once.

| Setting | Default | What it decides |
| --- | --- | --- |
| `companionSite` | `always` | Whether adding an app also blocks the website it is also at |
| `sendAdditions` | `ask` | Whether what this device adds is sent to the others |
| `acceptAdditions` | `ask` | Whether what another device adds is added here |

`companionSite` concerns this device alone and never crosses the link, but it is the same kind
of question and uses the same scale.

None of them waits out a delay. Turning one down blocks nothing that was blocked a moment ago.
It only stops adding. Under `never` for `sendAdditions`, a device sends nothing more. Under
`never` for `acceptAdditions`, an arrival is marked seen and passed over.

### The setup file, `ConfigExport`

The setup file is not part of the link. It is a file a person hands over, but a port has to
read one, so its schema is here (`schema/config-export.json`). The version is 1. The file is
pretty-printed with sorted keys and unescaped slashes, because someone may open and read it and
a stable key order makes two of them worth diffing. Dates are ISO-8601, the same as everything
else.

The top level has `version`, `platform` (`"ios"` or `"mac"`), `exportedAt`, an optional
`appVersion`, `loosenDelayHours` (the base loosening delay) and `targets`. Each target has a
`kind` (`"app"`, `"website"` or `"category"`), an optional `identifier`, `name` and `nickname`,
an optional `utility` (`"essential"`, `"useful"`, `"idle"` or `"hazard"`), an optional `rule`
and an optional `alsoBlocks`.

The file carries the part someone actually decided: which things are managed, what they are
called, how much each is worth, and when each is allowed. It leaves out the Anchor entirely.
The anchor's list is tokens and its key is a physical tag, so none of it would survive the
trip, and a file that looked as though it carried the Anchor would be worse than one that
plainly does not. It also leaves out the runtime, the pending queue and `LinkPreferences`.

`ExportedTarget.identifier` is a bundle identifier for a Mac app or a host for a website, and it
is nil for anything the phone knows only as a token. An import on a phone has to ask which app
this was, with `name` to ask about. `alsoBlocks` carries the other doors into the same thing,
and only as hosts, for the same reason. A website half that came from Apple's picker cannot
travel and is simply absent.

## 10. What a transport has to provide

`AnchorCloud` is a short enum over `NSUbiquitousKeyValueStore`. Any replacement has to answer
four things:

1. A keyed store that lists by prefix. It must set, get and remove a JSON blob under a string
   key, and enumerate every key that starts with `furlough.device.`, `furlough.revoke.` or
   `furlough.adds.`. Prefix listing is what lets the roster exist without a list that two
   devices would have to agree on. The whole store must hold one anchor record plus one entry,
   one possible revocation and one 20-deep ring per device.
2. A reachability probe that answers "will anything actually cross". The question "is this
   configured" is a different one, and confusing the two cost a day.
   `NSUbiquitousKeyValueStore.synchronize()` returned true on a Mac with iCloud Drive switched
   off while nothing crossed for half an hour, so the app reported a link that did not exist.
   The probe now reads `FileManager.ubiquityIdentityToken`. A port needs a probe with the same
   property. The answer has to be a standing state that the app keeps showing. A signed-out
   account does not resolve itself, and until it changes the devices are two separate installs
   that happen to look alike.
3. A change signal: something to observe, so a device reads again when another writes and does
   not have to poll. It must also be able to say when the account itself moved (signed in,
   signed out or switched), because what arrives after that belongs to a different person than
   what came before, and both the probe and the record have to be read again.
4. Identity scoping. The store must already be scoped to one person, with no key of Furlough's
   own. Everything above assumes that a device reading `furlough.device.*` sees that person's
   devices and nobody else's.

The iCloud key-value store supplies all four. Apple carries it under the user's own Apple
Account, it works with the devices apart, and the account is the identity, so there is no
pairing step, no key exchange and no account of Furlough's. A relay would supply (1) and (3)
easily and (2) with care, and it would not supply (4) at all. Without the Apple Account there
has to be a pairing step to establish that two devices belong to the same person, and there
have to be per-device keys so the relay cannot read what it carries.

That is a large job, and it is more than an engineering job. It would mean Furlough running a
server, which the privacy page says it does not do.

### What has no path today

A device without iCloud has no path. There is no relay and no fallback transport, and nothing in
this directory should be read as saying one is coming or that it would be small.

## 11. The rules engine

Sections 1 to 10 are the link. This section is the other half: what Furlough decides on one
device with nothing crossing at all. A port needs both. An Android build that syncs the anchor
perfectly and gets the windows wrong is not Furlough. The engine is pure, so a second
implementation can be held to it exactly.

The vectors are in `fixtures/policy/`, 48 of them, named by what they exercise: `status-`,
`transition-`, `classify-`, `pending-`, `night-`, `week-` and `spans-`.

### Time, and the calendar

Every vector is computed in one pinned calendar: Gregorian, GMT, `en_US_POSIX`, Sunday first. A
port has to pin its own before comparing, because the minute of the day, the weekday and the day
boundary all move with the time zone.

Weekday numbers are Calendar's (1 is Sunday and 7 is Saturday), and `TimeWindow.days` numbers
its bits the same way, with bit 0 for Sunday, so a weekday number and a bit position line up
without a conversion table. The bit sets the vectors use are 1 for Sunday, 4 for Tuesday, 62
for Monday to Friday, 64 for Saturday, 65 for the weekend and 127 for every day.

`now` is always Furlough's own time, never the device's wall clock. Every function that takes
one takes it as an argument, and nothing in the engine reads a clock.

### Status: `Policy.status`

This is the one question the shields ask. The answers are checked in this order, and the first
that applies wins:

1. `anchored`: the anchor holds any of this target's doors at `now`. This is read before the
   rule, always. An anchored target inside its open window is still anchored.
2. `unconfigured`: there is no rule. Nothing is enforced until the first rule is saved, and
   this status is allowed.
3. `blockedAllDay`: the rule allows no minute of any day.
4. `exhausted(nextOpen)`: today's budget is spent. Exhaustion is keyed by the day
   (`YYYY-MM-DD` in the pinned calendar), so yesterday's does not count.
5. `open(until:)`: now is inside a window. `until` is the window's end as a minute counted from
   the start of today, which is why it can exceed 1440 (see nights, below).
6. `closed(nextOpen)`: there is a window later today, or else the next day that has one.

`nextOpen` is `{minuteOfDay, daysAhead}`, where 0 is today and 7 is the same weekday next week.
The search runs over 1 to 7 and wraps, so a Saturday looks into Sunday and does not run off the
end of the week. A rule with no windows reopens at `{0, 1}`, which is only the day rolling over
and its budget resetting.

Only `open` and `unconfigured` let the thing through. Every vector records that as `isAllowed`.

### The next transition: `Policy.nextTransition`

This is the next instant at which some status can change, over the whole config. It is the
soonest window edge later today (a start strictly after now, or an end after now and before
midnight), or else the start of tomorrow. A timed anchor's `until` wins when it falls before
that. An edge already reached is not the next one: standing exactly on a window's start, the
answer is its end.

### Tightening against loosening: `Policy.classify`

**Tightening lands at once, and loosening waits out the delay.** That asymmetry is the whole
commitment device, so what counts as which is the most load-bearing rule in the engine.

For a rule, the test is `new.isTighterOrEqual(to: old)`, where a missing rule on either side
reads as unrestricted: every minute allowed and a full day of budget. So a target's first rule
is always a tightening, and removing a rule is always a loosening. "Tighter or equal" is
checked day by day for all seven days: no minute is allowed that the old rule forbade, and no
day has a larger budget. Two hours moved off Sunday onto Monday leave the week the same size
and Monday looser, and a looser Monday is a loosening. Equal is a tightening. Writing one
budget out as seven equal ones changes no day, so nothing queues.

For a tier, the comparison is the delay the tier buys. A tier changes nothing about what is
blocked. It changes only how long the next loosening waits. Moving toward hazard
lengthens the wait and lands now. Moving toward essential shortens the wait and queues, which is
what stops "mark everything essential" from being a way out of the delay.

### Pending changes landing: `Policy.applyDuePending`

A pending change is one of `setRule`, `removeTarget`, `setDelay`, `setUtility`, `unlink` or
`setAnchorSchedules`. Every change whose `effectiveAt <= now` is applied in `effectiveAt` order
and then removed from the queue. The comparison is `<=`, so a change due at this very instant
lands. A change whose target no longer exists applies to nothing and is still spent and counted.

Two things a port could implement halfway and still pass a naive test:

- `Forgiveness.expire` runs first. It ends the first-week trial once its date has passed, and it
  clears every undo window that has closed. Either one counts as a change, so on its own it
  makes the pass report one. An undo closing is a change coming due like any other, and it is
  not something compared against the clock on every read.
- This is the one place a landing is counted into the record. The vectors carry `landedToday`
  for that reason.

### A window crossing midnight

A stored window never crosses midnight. A night is written as two windows: an evening that ends
at 1440 on the days it starts, and a morning that starts at 0 on the days after. The bit set is
shifted one day on, so a Saturday night's morning half is a Sunday. An evening that runs to
exactly midnight has no morning half and splits into itself.

`folded` is the exact inverse of that split. The two windows and the one night allow the same
minutes of the week, so a night reads back as the row it was written as.

A night is one window to whoever is using it, so nothing shuts at the join and nothing says it
does. Inside the evening half, the status reports the morning it really ends: 1680 for a 5 PM
to 4 AM night. The exception is a morning worth no minutes. Then there is no morning half to
run into, and the night really does end at 1440.

### Per-weekday budgets

A rule carries either one `dailyBudgetMinutes` or seven `budgetByWeekday`, Sunday first. Every
read goes through one accessor, which answers the single number seven times over when there is
no array. Nothing downstream ever has to know which kind of rule it is holding.

The rule that catches people out is that a day worth no minutes has no open hours at all. Its
windows are not offered, the status reads closed from the hours alone, and the next-open search
skips it. That is also why a Saturday night stops at midnight when the Sunday is worth nothing.

Saving normalizes. Seven equal days say nothing that the one number does not, so the array is
dropped and the single figure is replaced with what the week actually said. Underneath a real
per-weekday budget, `dailyBudgetMinutes` is a shadow that can be any figure at all. That is why
an editor collapsing seven sliders back to one is offered the representative budget: the figure
most days already carry, and the smaller of two that tie.

### The delay arithmetic

`classify` decides whether a change waits. `Config.delayHours` (in `Utility.swift`) decides how
long. Each tier has a multiplier: essential 0.25, useful 1, idle 2 and hazard 4. A target with
no tier counts as useful. The wait is the base `loosenDelayHours` (24 by default) times the
tier's multiplier, rounded to the nearest whole hour and never less than 1. During the first
week (`Furlough.trialDays`, 7 days from when Screen Time access was first granted) the wait is
capped at 1 hour. The multipliers live in the Swift. `tables/tiers.json` records which tier
each thing has and does not hold them.

### Spans: `ActivityLimit.spans`

A caveat before the vectors: the ceiling here is Apple's. iOS allows 20 DeviceActivity
activities (`Furlough.maxActivities`), and one of them is the daily budget tracker. The phone's
editor therefore refuses a rule that would need more than 19 (`ActivityLimit.maxSpans`) while
the rule is still a draft. That count is wider than window spans. `ActivityLimit.activities`
adds one for each distinct drop minute and each distinct lift minute in the anchor's schedules,
queued schedules included, and one for a timed anchor's own `until` while it holds. The vectors
cover only the window part, `ActivityLimit.spans`. A port has its own scheduler and its own
ceiling, or none, and should not inherit that number.

What does carry over is the decomposition, which belongs to the rule set and not to Apple. The
distinct spans that a config asks to be watched are every window of every saved rule and every
queued `setRule` for a target that still exists, with the days stripped, and nothing at all from
a rule that never allows anything. The same hours on different days are one span, because the
scheduler is told about hours and the engine decides the day. A queued loosening sits beside the
rule it will replace, so both sets of hours are live at once. Counting only the new rule would
let through exactly the edit that overflows.

Per-weekday budgets do not press on this at all. A budget is an event carried by the day
activity, and it needs no activity of its own.

### A moved time zone

The vectors above are all decided in the pinned calendar. On a device, `Policy.decide`,
`Policy.statuses` and `Policy.summary` also exist in forms that take a `Clock.ZoneReading`, and
every caller that derives shields goes through those. When the device's zone differs from the
one Furlough last honoured, the old zone stays honoured beside the new one for a hold. Each
status is then decided twice, once in each zone, and the tighter answer wins (`Policy.tighter`).
Anchored beats everything, and a shut answer beats an open one. Between two shut answers the
later reopening wins, and between two open answers the earlier close wins. Budgets are keyed by
the day in the held zone, so a day that rolled only because the zone moved does not refill them.

The hold lasts the base loosening delay (`SharedState.zoneHold`): 24 hours by default, and 1
hour in the first week. The mark of the honoured zone is `runtime.zone`. It is device-local, it
is never exported, and it never waits out a delay. `Tests/Core/ZoneTests.swift` covers it. No
vector does.

### What these vectors do not cover

Named so nobody mistakes the set for the whole engine:

- `Policy.decide` is the projection of every status onto what a platform actually blocks. It is
  genuinely two functions, one for each platform, because an iOS shield takes Screen Time
  tokens and the Mac's takes bundle identifiers and hosts. A port writes its own, and the
  statuses above are its input.
- `Policy.summary` is what a widget and a Live Activity read. It is presentation.
- The record (`Record.swift`) is what happened, counted for two screens. Nothing that decides
  what is blocked ever reads it, which is the point of it.
- The delay arithmetic and the time zone hold, both described above, have no vectors.

## 12. The tables

`tables/` is the part of Furlough that is knowledge instead of logic: which things are the same
thing under two names, what each is worth, and what rule to start it on. All of it is offline
and exact, so a port loads these files and does not re-derive them. Three of the four are
dumped straight from the Swift by the same test that checks the fixtures, so they cannot drift.

| File | From | Holds |
| --- | --- | --- |
| `companions.json` | `Companions.pairs` | 83 pairs, in table order: `title` (the first name, what to call it), every `names` it is written as, every `bundleIDs` it ships under on either Apple platform, and the `hosts` it lives at. |
| `tiers.json` | `AppUtility` | What a thing is worth, keyed four ways: `names` (152), `bundleIDs` (133), `bundleIDPrefixes` (13) and `hosts` (98). Each row is a `key` with a `utility` of essential, useful, idle or hazard, and a `detail` on the essentials, where saying the specific harm beats the generic line. |
| `rule-suggestions.json` | `RuleSuggestion` | The 30 per-app exceptions to what a tier alone suggests, with the tier each was written against (11 by name, 10 by bundle identifier, 9 by host). A row carries `budgetMinutes` and an optional `window`. These are judgements, not facts, and they can be retuned any afternoon, which is why they are a separate table from the tiers. |
| `other-platforms.json` | hand-filled | What each companion pair is called on Android and Windows, keyed by pair title. Each entry has an `android` array and a `windows` array, and a `$note` key at the top explains the rules. Every `android` array is filled except one, and each entry was confirmed against its own Play listing. `windows` is empty throughout and undecided. See [Not decided](#not-decided). |

How each table matches:

- Companion names match after trimming the ends and lowercasing. Bundle identifiers match after
  lowercasing and dropping a `maccatalyst.` prefix. Hosts match subdomains (a leading `www.` is
  ignored), and the longest matching rule wins.
- In `tiers.json`, names match the same way. Bundle identifiers match exactly, or else by
  prefix: a prefix matches exactly or up to a dot, and the longest prefix wins, so a vendor's
  suite lands together and `com.ubercabbage` is not Uber. Hosts match subdomains, and the
  longest wins.

Two things a tier table is not: it never blocks anything, and it never applies anything. It is
offered and argued with in an editor, and the engine that decides what is shielded has never
read it.

## Not decided

These are open questions. None of them is described above as if it were settled, and none
should be built without asking Zach.

- The relay. See §10. Everything non-Apple depends on it. The open part is whether to build it
  at all, because the implementation follows from that decision.
- `canRelease` in the merge. `merge` accepts a release only from `origin == tagScan` and
  `platform == phone`. The roster already carries `canRelease` per device, and switching the
  merge to read it is a one-line change that has not been made. Today the two agree, because a
  phone is exactly what has a reader, so nothing observable turns on it. It would matter the
  moment a platform has readers on some devices and not others, which is where Android lands.
- Platform values beyond `phone`, `pad` and `mac`. Adding one is not free. An older build that
  reads an unknown platform drops the whole entry (§3), so a device on a new platform is
  invisible to every device that has not been updated. What that should do, and whether it
  needs a version field that the current record has no room for, is unanswered.
- Whether extensions may write the roster and the rings. This has been open since the Anchor
  first crossed. The monitor extension already writes the anchor record, for a scheduled drop
  and for a lift. Today the roster and the rings are only ever written by the apps.
- `tables/other-platforms.json`, the `windows` column. This column holds Windows executables
  per companion pair and still ships with no values. The house rule is that every entry is
  confirmed from a vendor source, and most Windows executables cannot be confirmed from a vendor
  page at all, so the column would stay largely empty however much work went into it. What
  would count as a confirmation there is the undecided part, and until it is decided nothing
  is guessed.

  The `android` column was the same decision until 2026-09-11, when Zach asked for the
  groundwork that a Kotlin port needs before the port itself exists. It is now filled for 82 of
  the 83 pairs. Each was confirmed against its own listing at
  `https://play.google.com/store/apps/details?id=<package>`, which had to answer 200 and name
  the app in its `og:title`. A 200 alone proves only that some app owns that identifier, not
  that it is the right one. `theScore Bet` is the one left empty. Its sportsbook left the US and
  the remaining listing is regional, and the neighbouring theScore news app is a different
  product, so standing it in would be exactly the guess that the rule forbids. Anything that
  cannot be confirmed stays empty.

## Using the fixtures

Every file is `{ "name", "function", "input", "expected" }`. `function` names the Swift function
that the vector exercises, so the folders are organization and the field is the contract.

There are 90 vectors. The link has 42: 11 for `merge`, 6 for `macDrop`, 9 for the roster, and
16 for the ring, the watermark and the landing. The engine has 48, all in `policy/` and named
by their prefix: 13 for `status` (two of them nights), 6 for `nextTransition`, 12 for
`classify`, 6 for `applyDuePending`, 3 for splitting and folding a night, 5 for a week of
budgets and 3 for spans.

Inputs are written by hand and use fixed ISO-8601 dates, never a clock. Expectations are
written by the code. Run the test with `FURLOUGH_WRITE_FIXTURES=1` in the test process's
environment, and every `expected` is rewritten from the current behavior instead of asserted,
and so are the files under `tables/` that are dumped from the Swift. A change in behavior
therefore fails the test until someone regenerates on purpose, and the diff of these files is
the review.

Run the commands from the repository root. The Xcode project is generated from `project.yml`
and is not committed, so run `xcodegen generate` first when `Furlough.xcodeproj` is missing
(`scripts/furlough gen` does the same). To check the vectors:

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

`scripts/furlough test` runs the same command. The repository's `CLAUDE.md` says to read the
result from the line that starts with `✔ Test run`, because the XCTest line `Executed 0 tests`
appears on a full passing run and means nothing.

To regenerate the vectors and the tables, use the command below. The `TEST_RUNNER_` prefix is
how a variable reaches the test process. `xcodebuild` does not hand its own environment to the
runner, and without the prefix the flag is silently ignored and the run simply asserts:

```bash
TEST_RUNNER_FURLOUGH_WRITE_FIXTURES=1 xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

The same run checks `tables/` against the Swift tables and each `schema/` file against a real
encode. Every key that the encoder writes must be a property the schema names, every property
the schema requires must be written, and each enum's raw values must equal the schema's `enum`
list. For `other-platforms.json` the run checks only that every key is a real companion title.
It cannot check the values, which is the reason for the vendor-source rule.

Three notes for a second implementation:

- The expectations are projections, not whole objects, where the whole object would be noise.
  `appended` is checked by the resulting ring's ids and sequences in order, because that is all
  it decides, and it never alters an entry's contents. `unseen` is checked by
  `{origin, sequence, title}` in order. `merge`, `macDrop` and `applyDuePending` are checked by
  the whole thing they produce, because no projection of it would be less than the thing
  itself. Some expectations also record the words a person sees, so a port renders the same
  ones: the `message` of a `macDrop` or leave refusal, the `others` sentence of `hasKey`, and
  the `summary` sentence of a landing.
- Inputs are minimal, and that is legitimate. `Config`, `AnchorProfile`, `Rule` and
  `RuntimeState` all have tolerant decoders, so a fixture writes only the fields the case is
  about and everything else takes its default. A port's own reader must be equally tolerant:
  `"runtime": {}` is a real, valid runtime.
- Pin the calendar before comparing anything under `policy/`: Gregorian, GMT, `en_US_POSIX`,
  Sunday first, and weekday numbers 1 to 7 with 1 as Sunday. Run these against a local time zone
  and roughly half of them will disagree for reasons that have nothing to do with the engine.
