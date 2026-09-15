# The contract

Furlough in a form that is not Swift: what crosses between a person's devices (§1–§10), and
what one device decides on its own (§11).

The link is four JSON values in a key-value store. The engine is a handful of pure functions
over a rule. This directory writes down the shape of both, plus 90 test vectors generated from
the Swift so a second implementation can prove it agrees. Nothing here is a port, a relay or a
transport; it is the thing all three would have to be built against.

It describes **what the code does today**, not what it might become. Where a rule looks like
it wants to change, that is said under [Not decided](#not-decided) and the rule above it still
states what actually runs.

| | |
| --- | --- |
| `README.md` | this file: the contract in words |
| `schema/` | JSON Schema (draft 2020-12) for each value that crosses |
| `fixtures/merge/`, `mac-drop/`, `roster/`, `additions/` | the link: 42 vectors |
| `fixtures/policy/` | the rules engine: 48 vectors |
| `tables/` | the identity tables, dumped from the Swift |

The Swift these come from: `Shared/Core/AnchorSync.swift`, `DeviceLink.swift`,
`SharedAdditions.swift`, `LinkFlow.swift`, `ConfigExport.swift` for the link; `Policy.swift`,
`Models.swift` and `ActivityLimit.swift` for the engine.
`Tests/Core/ProtocolFixturesTests.swift` runs every fixture against the real code and checks
every schema against a real encode.

---

## 1. What crosses, and what never does

Three kinds of thing cross: **the anchor's state**, **the roster of devices**, and **the name
of something you added**. That is the whole list.

What never crosses, and cannot be made to:

- **Screen Time tokens.** An `ApplicationToken`, `WebDomainToken` or `ActivityCategoryToken` is
  an opaque blob Apple scopes to one device and one install of one app. It means nothing off
  the phone that minted it. So a phone can never send "this app"; it can only send what it has
  *learned* the app is called.
- **Rules, as such.** A rule travels only as a passenger on an addition — the sender's `Rule`
  for the thing it just added — and only lands where the receiver's row has none. There is no
  rule sync, no shared list of targets, and no way for one device to edit another's rules.
- **The Anchor's list.** `AnchorProfile.kinds` is tokens on the phone and bundle identifiers on
  the Mac. Each device keeps its own; only whether the anchor is *down* crosses.
- **The setup file.** `ConfigExport` (§9) is a file a person hands over by hand. It never goes
  through the link and is documented here only because a port has to read one.

Everything that crosses is per-device state that a device writes about *itself*. There is no
shared document, so there is nothing for two devices to fight over.

### The gate

**A device that is not enrolled reads nothing and writes nothing.** Enrollment is opt-in, per
device, and it gates everything, the Anchor included. `AnchorSync.pull` returns immediately
when this device is off the link — the record is not read and refused, it is *not read* —
and `SharedAdditions.pending` returns empty.

A record written by a device that is not on the roster is refused even when this device is
enrolled: `pull` accepts a record only when `remote.writer == deviceID` or
`roster.isLinked(remote.writer)`. A record left behind by a device that has since left is a
lock with no owner.

Grandfathering is the one exception, and it is not an exception to the gate — it is how an
install that predates the roster answers the enrollment question without being asked.
`DeviceLink.grandfathers(lastHeard:phoneSeen:)` is `lastHeard != nil || phoneSeen`: a device
that has ever read the *other* device's write enrolls itself on first launch; one that has
only ever heard itself, or nothing, starts off the link and is shown the guide. The question
is settled once and latched under `furlough.link.decided`.

---

## 2. The four keys

Every value is JSON, stored as `Data` under a string key in one flat key-value namespace.
There are no nested containers and no lists to keep in step: the roster and the rings are
found by **listing keys by prefix**.

| Key | Value | Written by | Removed |
| --- | --- | --- | --- |
| `furlough.anchor.v1` | one `AnchorRecord` | whichever device last changed the anchor | never in normal use; debug reset only |
| `furlough.device.<id>` | one `LinkedDevice` | that device, about itself | by that device on leaving, or on obeying a revocation |
| `furlough.revoke.<id>` | one `Revocation` | any linked device, about another | by `<id>` itself when it re-enrolls |
| `furlough.adds.<id>` | array of `SharedAddition`, at most 20 | that device, about what it added | with the device's entry, on leaving or revocation |

`<id>` is the device's own identifier: a UUID string made once per install and kept in the App
Group, so every process on the device signs the same way (`AnchorSync.deviceID`). It is the
same string that appears as `AnchorRecord.writer`, `LinkedDevice.id`, and
`SharedAddition.origin`.

**Lifetimes.**

- The **anchor record** is a single slot, overwritten by every write. It has no history; the
  `sequence` is what orders writes, not the store.
- A **device entry** lives as long as the device is on the link. It is rewritten — not just
  touched — on every enrollment and beside every addition, so `lastSeen` means what it says.
  `enrolledAt` is carried over from the existing entry on a rewrite, so a refresh never spends
  a revocation that has not been read yet.
- A **revocation** outlives the device entry it kills, and is spent rather than deleted: a
  revocation whose `at` is older than the entry's `enrolledAt` is ignored, because the device
  was taken off and came back. It is deleted only when the named device re-enrolls
  (`enroll` removes `furlough.revoke.<own id>`).
- A **ring** is a rolling window of the last 20 additions from one device. It is not a queue:
  nothing consumes from it. Receivers track their own position (§7).

### Ordering, and why it is per-key

There is **one** monotonic counter shared between devices — `AnchorRecord.sequence` — and it
is monotonic by construction rather than by agreement: every write sets it one past anything
either device has seen (`AnchorProfile.sequence`, incremented on each local drop, and adopted
from the remote on each merge). A record whose sequence is not strictly greater than the local
one changes nothing.

Addition sequences are **per sender** (`furlough.link.sequence`, one higher on every send) and
are never compared across senders. A receiver keeps one watermark per source.

---

## 3. The values, field by field

### Encoding

Every value that crosses is encoded by `AnchorCloud`:

- `JSONEncoder` with `dateEncodingStrategy = .iso8601`, decoded with the matching
  `dateDecodingStrategy`. So **every date is an ISO-8601 string** — `"2026-09-08T12:00:00Z"`.
  Foundation's `.iso8601` writes UTC with a `Z` and no fractional seconds, and reads the same.
- No key sorting and no pretty-printing: these are blobs, not files. (`ConfigExport` is the
  opposite and says so — §9.)
- A `UUID` is its uppercase string: `"6BA7B810-9DAD-11D1-80B4-00C04FD430C8"`.
- Absent optionals are **omitted**, not written as `null`. A reader must treat a missing key
  and a null the same way.
- An entry that will not decode is **skipped, not fatal**: `DeviceLink.roster()` drops a device
  whose entry it cannot read — written by a newer build with a platform this one does not know
  — rather than failing the whole read. A port must do the same, and must therefore never
  assume the enums below are closed.

### `AnchorRecord` — `furlough.anchor.v1`

What one device says about the anchor, as the other receives it. The anchor's *state* and
nothing else.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `sequence` | integer | yes | Monotonic across all devices; every write is one past anything either has seen. |
| `isAnchored` | boolean | yes | Whether the writer's anchor is down. |
| `anchoredAt` | date | no | When it went down. |
| `until` | date | no | When a timed hold ends. Absent means only the tag lifts it. |
| `writer` | string | yes | The writing device's id. |
| `platform` | `"phone"` \| `"pad"` \| `"mac"` | yes | What wrote it. |
| `origin` | `"drop"` \| `"tagScan"` \| `"lift"` | yes | How the write came about. |
| `writtenAt` | date | yes | The writer's Furlough time at the write. |

`platform` is three cases because an iPad runs the phone build and has **no tag reader**: it
can be anchored and can never release, which is the Mac's position. Core has no UIKit, so the
app notes the idiom at launch and every process reads the note.

`origin` values:

- `drop` — by hand, from a widget or Control Center, or by the schedule.
- `tagScan` — the one release: a paired tag read by a phone.
- `lift` — a timed anchor's `until` passed. **Informational.** The receiver computes the same
  expiry from the `until` it already holds, and `merge` refuses a `lift` as a release.

### `LinkedDevice` — `furlough.device.<id>`

What one device says about itself to the others.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | string | yes | The device id. Equals the `<id>` in the key. |
| `name` | string | yes | What the person called it. Trimmed; falls back to the platform's word. |
| `platform` | `"phone"` \| `"pad"` \| `"mac"` | yes | Same enum as the record. |
| `enrolledAt` | date | yes | When it joined. A revocation older than this is spent. |
| `lastSeen` | date | yes | When it last wrote anything. |
| `canRelease` | boolean | yes | Whether a tag can be read on it. |

`name` is typed by the person on a phone — iOS stopped telling third-party apps the device's
name in iOS 16 — and offered from `Host.localizedName` on the Mac. An empty or whitespace-only
name becomes `"iPhone"`, `"iPad"` or `"Mac"` (`LinkedDevice.defaultName(for:)`).

`canRelease` is written as `platform == .phone`. It is a **fact about the hardware**, not a
preference: only an iPhone has a reader. See [Not decided](#not-decided) — the roster carries
it, and `merge` does not yet read it.

### `Revocation` — `furlough.revoke.<id>`

One device taking another off the link, written under the *revoked* device's id so that device
finds it on its next read.

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `by` | string | yes | The revoking device's id. |
| `at` | date | yes | When it was written. |

Any linked device may write one. The named device un-enrolls itself on its next read
(`obeyRevocation`, called from `AnchorSync.pull`, so it lands in whichever process reads
first). Meanwhile every other device already leaves it out of `Roster.linked`, so a revocation
takes effect for everyone else immediately and for the revoked device on its next read.

### `SharedAddition` — an element of `furlough.adds.<id>`

One thing a linked device added, as the others receive it: what it is called and every
identifier and host it goes by. **Never a token.**

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | uuid | yes | The *sender's* target id. A second write about the same thing replaces the first in the ring. |
| `sequence` | integer | yes | One higher on every write from this sender. What the receiver's watermark counts. |
| `title` | string | yes | What to call it: `"YouTube"`, or the host when nothing better is known. |
| `isApp` | boolean | yes | Whether the sender's face was an app. |
| `bundleIDs` | array of string | yes | Lowercased bundle identifiers it is known by, on either platform. May be empty. |
| `hosts` | array of string | yes | The hosts the sender actually blocks for it. May be empty. |
| `rule` | `Rule` | no | The sender's rule, if it had one yet. |
| `half` | `"rules"` \| `"anchor"` | yes | Where it was added. |
| `origin` | string | yes | The sending device's id. Equals the `<id>` in the ring's key. |
| `platform` | `"phone"` \| `"pad"` \| `"mac"` | yes | What the sender was. |
| `addedAt` | date | yes | When it was sent. Receivers order by this. |

`Rule`, when present, is the store's own rule shape:

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `windows` | array of `TimeWindow` | no (absent = none) | Allowed spans. No windows means open all day up to the budget. |
| `dailyBudgetMinutes` | integer | yes | Minutes a day in total. |
| `budgetByWeekday` | array of 7 integers | no | Sunday first. **Anything but exactly seven entries decodes as absent** — the safe reading of a damaged field is the rule's one budget, never a day with no limit. |

`TimeWindow`:

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `startMinute` | integer 0–1440 | yes | Minutes from midnight. |
| `endMinute` | integer 0–1440 | yes | Exclusive; 1440 is midnight. |
| `days` | integer 0–127 | no (absent = 127) | Bit set, **bit 0 is Sunday**, so bits line up with Calendar's 1…7. |

A stored span never crosses midnight: an evening that runs late is an evening window plus an
early-morning window on the next day, with the second window's `days` shifted one day on.

### What a sender can and cannot describe

`SharedAdditions.describe` returns nothing at all for some targets, and a port that sends must
know which:

- A **category** never travels. There is no name a receiver could act on.
- A **picked app or website** (an iOS token) travels only once the phone has learned its name
  — from the shield, or from Screen Time's own tables. Until then `describe` returns nil and
  the target sits in `LinkFlow.awaiting`. On a phone the addition may follow the add by hours.
- A **typed host** and a **Mac app** name themselves and travel at once.

Where the companion table (`tables/companions.json`) knows the thing, the addition carries the
table's title and the table's bundle identifiers alongside whatever the sender had. So YouTube
goes out as `"YouTube"` with `com.google.ios.youtube` beside it whichever half was added.

---

## 4. Merging the anchor

`AnchorSync.merge(local:remote:now:)` is pure and returns a profile and a note. `now` is
**Furlough's own time**, never the wall clock.

The branches, in order — the first that applies wins:

1. **Stale.** `remote.sequence <= local.sequence` → nothing changes at all, not even the
   sequence. Note: `stale record (N is not past M)`.

   Otherwise the local sequence is set to the remote's *before* anything else is decided, so
   every branch below moves the sequence on even when it changes nothing.

2. **A release** (`remote.isAnchored == false`):
   - Accepted only when `origin == "tagScan"` **and** `platform == "phone"`. Anything else:
     `refused a release that was not a phone's tag scan`. That covers a Mac writer, an iPad
     writer, an `origin` of `lift`, and an `origin` of `drop` with `isAnchored` false.
   - Accepted, but nothing is holding here (`!local.isHolding(at: now)`):
     `released by the phone; already up here`.
   - Accepted and something is holding: `isAnchored` false, `anchoredAt` and `until` cleared.
     Note: `released by the phone's tag`.

3. **A drop already over by this clock.** `remote.until != nil && remote.until <= now` →
   nothing else changes. Note: `a drop already over by this clock`. This is why a `lift` needs
   no special handling: the receiver reaches the same conclusion from the `until` it holds.

4. **Something is already holding here.** The tighter of the two `until`s wins
   (`Policy.tighterUntil`: an absent `until` is tighter than any date, because it means only
   the tag lifts it). If that is what is already held: `already anchored here`. Otherwise the
   hold is lengthened: `hold lengthened by the other device`.

5. **Nothing holding here.** `isAnchored` true, `anchoredAt` from the record or `now` when it
   has none, `until` from the record. Note: `anchored by the other device`.

**A remote `until` is always judged by this device's clock.** A drop that is already over here
does not drop here, and a drop over an anchor already down can only ever lengthen the hold.

`AnchorSync.pull` wraps this with the gate (§1) and two side effects worth porting: `phoneSeen`
latches the first time a `phone`-platform record is read, and `lastHeard` is stamped for any
record this device did not write — *before* the merge, and whatever the record turns out to
say. A record that changes nothing here still proves the two devices are talking, and that is
the whole question the link status answers. Hearing yourself is not evidence of anything.

Vectors: `fixtures/merge/`.

---

## 5. The Mac's drop

`AnchorSync.macDrop(_:now:hasKey:cloudAvailable:)`. The Mac has no tag, so it takes no `until`
and does not ask `canAnchor`. It first lifts an expired anchor, then refuses in this order:

1. `noList` — `!config.anchor.hasSomethingToHold`. Nothing on the list and the scope is not
   everything-except.
2. `noCloud` — the store is unreachable.
3. `noPhone` — no device on the roster besides this Mac can release.
4. `alreadyAnchored` — the anchor is already down here.

Otherwise it drops: `isAnchored` true, `anchoredAt` = `now`, `until` cleared, `sequence` + 1.

**The order is load-bearing.** `noCloud` is checked before `noPhone` because it is the one that
makes the other unanswerable: what the roster says was read from an account this Mac may no
longer be signed in to, so trusting the roster alone would let exactly the lock-with-no-key
through that the guard exists to stop. They are the same guard wearing two faces — *a Mac must
never hold an anchor whose key cannot reach it* — and they are checked in the order they can
be fixed in.

`hasKey` is `Roster.hasKey(besides:)`: some device other than this one, on the link, with
`canRelease`. It replaced a latch set the first time a phone was ever heard from, which stayed
true after that phone left.

`DropRefusal` has two more cases, `nothingToAnchor` and `tooSoon`, which belong to `Policy.drop`
— the phone's, which does take an `until`. `macDrop` cannot return either.

Vectors: `fixtures/mac-drop/`.

---

## 6. The roster, and leaving

`Roster` is `devices: [LinkedDevice]` and `revoked: [deviceID: Revocation]`, read from whatever
hands it the entries.

- **`linked`** — the devices on the link: written, and not revoked since they enrolled. A
  revocation is applied when `revocation.at >= device.enrolledAt`, and spent when
  `revocation.at < device.enrolledAt`. Sorted by `enrolledAt`, oldest first.
- **`isLinked(id)`**, **`device(id)`**, **`others(than:)`** all read `linked`.
- **`hasKey(besides: id)`** — some device other than `id` in `linked` has `canRelease`.
- **`othersDescription(than: id)`** — "your other devices" for none, "your iPhone" for one,
  "your Mac and iPad" for two, and a comma list with a final "and" beyond that.

**Leaving.** `DeviceLink.leaveRefusal(anchorHoldsHere:anchorHoldsOnLink:)` refuses with
`.anchored` when either is true, and otherwise permits. Both leaving and revoking another
device take the same refusal: the anchor holding anywhere makes every device a party to it.
Taking a device off while it holds would either leave that device locked with no key or
release it, and both are the one thing the Anchor exists to make impossible.

The message: *"The anchor is down. Scan your tag to release it, and then any device can be
taken off the link."*

`anchorHoldsOnLink` is `DeviceLink.recordHolds(record, now:)` — the shared record is anchored,
and either has no `until` or has one still in the future by this device's clock.

Leaving is otherwise **instant**: with no anchor down the link holds nothing that leaving would
let go of. Leaving removes this device's own entry and its own ring, and sets enrollment false.

Vectors: `fixtures/roster/`.

---

## 7. The ring, the watermark, the declined set

Each device publishes to a ring of its own; every other device keeps its own position in each
ring. No shared list, so nothing to fight over, and a device that was off for a week reads the
rings and catches up.

**Writing** — `SharedAdditions.appended(ring, addition)`:

1. Drop any existing entry with the same `id`. A second write about the same thing — its first
   rule landing — replaces the first rather than sitting beside it.
2. Append.
3. Sort by `sequence` ascending.
4. Keep the **last 20**. Enough to cover a week away; small enough that the whole store stays
   far under the store's megabyte.

**Reading** — `SharedAdditions.unseen(rings:watermarks:declined:thisDevice:roster:)` returns,
oldest `addedAt` first, every addition such that:

- its source is not this device, **and**
- its source is in `roster.linked`, **and**
- `sequence > watermarks[source] ?? 0`, **and**
- its `id` is not in `declined`.

**The watermark** is per source and moves only forward: `markSeen` sets
`watermarks[addition.origin] = max(existing, addition.sequence)`. It moves whether or not the
addition landed — landed, declined, or nothing-to-do all mark it seen.

**The declined set** is kept separately from the watermark, and that separation is the point: an
addition still waiting for an answer under Ask is *below* the watermark and *not* declined,
which is what makes it show again on the next read. Declining sets both.

Vectors: `fixtures/additions/`.

---

## 8. What a receiver does with an addition

`SharedAdditions.landing(for:in:installed:companion:now:)` decides; `land` performs. `landing`
writes nothing, so under Ask a person can be shown exactly what would happen. It takes a clock
because one of the four things it decides — the anchor's list — is read against the anchor's
own state at that instant.

**Finding an existing row**, in this order:

1. By host — any of the addition's hosts already covered by a row. Both platforms answer this
   exactly.
2. By bundle identifier — **Mac only**.
3. By learned name — the addition's title against a row's `systemName`, normalized; or a row
   whose name is in the companion table with one of the addition's bundle identifiers.

**The app half.** Only when `isApp` and the found row does not already cover an app:

- **Mac**: the first of the addition's bundle identifiers that is *installed here* and is not
  already a row. `installed` is a map of normalized bundle identifier to name, walked from the
  Applications folders — and only when something is actually waiting, because that is not a
  thing to do on every poll. Nothing installed: no app half, and the hosts still land.
- **Phone**: `appNeedsPicker` is set. Nothing here can mint a token, so the site half lands and
  the app half becomes a nudge towards Apple's picker.

**The hosts.** The sender's hosts, plus — when this device's `companionSite` is `always` — the
companion table's hosts for the addition, minus every host already covered by a row. So a Mac
with no YouTube app installed still lands `youtube.com`.

**The rule.** The addition's rule, but only where the found row has none. *A rule of your own
is never overwritten by a device you are not holding.*

**The anchor's list — `anchors`.** Set when the addition was made to the anchor's half and
*this* anchor can take one: it is not holding at `now`, since nothing changes the list under a
lock, and its scope is not everything-except, where the list is what stays *open* and so never
grows by an addition. Given that, it is set whenever something new arrives (an app or a host),
and — where nothing new arrives — only when the row that already covers it is not on the list
already. **It is a field of its own because it is the one thing left to do when there is
nothing to block:** a Mac that already blocks YouTube still needs to hear "hold it here too",
and dropping that would let the arrival go missing.

`isNothing` is true when there is no app to add, no host to add, no rule to give, no change to
the anchor's list, and no app owed — the caller marks it seen and moves on without asking
anybody anything. **Owed** (`owesAnchoredApp`) is the phone hearing that an app was anchored
elsewhere: `appNeedsPicker` with `half` `anchor`. There is nothing to block by name, but
Screen Time's tables may yet match the app to a token, and otherwise the offer is how a person
learns the picker is the way in — so it is shown rather than swallowed.

**`land` is a tightening**, every part of it: more is blocked than a moment ago, so it lands at
once with no delay, and a rule it brings wears the undo window exactly as a rule saved by hand
does (`RuleUndo(rule: nil, savedAt: now)`). Where `anchors` was set, the rows it touched go
onto the anchor's list — **re-checked against the clock rather than trusted from the landing**,
because under Ask time passes between the offer and the answer and the anchor may have dropped
meanwhile. A port that decides once and performs later must re-check the same way.

### The shape differs by platform, on purpose

| | Phone | Mac |
| --- | --- | --- |
| App and its site | **one row.** Hosts are linked onto the row (`Target.also`) | **a row each.** The app is one row, each host another |
| App the receiver lacks | cannot be added; offered through Apple's picker | added when installed, skipped when not |
| Rule | given to the row that has none | given to each row it creates that has none |

The phone has held an app and its site as one row since 2026-09-08 (one habit, one row). The
Mac has never drawn a linked half, and there each host is a row of its own exactly as its
companion sheet adds them: **a linked half the Mac's editor could not show would be a block
with no handle.** A port must pick one of these two shapes and say which; it is a fact about
that platform's editor, not about the contract.

---

## 9. The three settings

`Config.link: LinkPreferences`, per device, `decodeIfPresent`, and **never exported** in the
setup file. Each is `always` | `ask` | `never` — three answers and never a fourth, so a person
learns the scale once.

| Setting | Default | What it decides |
| --- | --- | --- |
| `companionSite` | `always` | Whether adding an app also blocks the website it is also at |
| `sendAdditions` | `ask` | Whether what this device adds is sent to the others |
| `acceptAdditions` | `ask` | Whether what another device adds is added here |

`companionSite` is not really about the link — it is about this device alone — but it is the
same kind of question and the same scale.

**None of them waits out a delay.** Turning one down blocks nothing that was blocked a moment
ago; it only stops adding. Under `never` for `sendAdditions` a device writes no ring at all;
under `never` for `acceptAdditions` an arrival is marked seen and passed over.

### The setup file, `ConfigExport`

Not part of the link — a file a person hands over — but a port has to read one, so its schema
is here. Version 1. Pretty-printed, keys sorted, slashes unescaped: this is a file someone may
open and read, and a stable key order makes two of them worth diffing. Dates are ISO-8601, the
same as everything else.

It carries the part someone actually decided: which things are managed, what they are called,
how much each is worth, and when each is allowed. It leaves out the Anchor entirely — its list
is tokens and its key is a physical tag, so none of it would survive the trip, and a file that
looked like it carried the Anchor would be worse than one that plainly does not. It also leaves
out the runtime, the pending queue, and `LinkPreferences`.

`ExportedTarget.identifier` is a bundle identifier for a Mac app or a host for a website, and
**nil for anything the phone knows only as a token** — an import on a phone has to ask which
app this was, with `name` to ask about. `alsoBlocks` carries the other doors into the same
thing, and only as hosts, for the same reason: a website half that came from Apple's picker
cannot travel and is simply absent.

---

## 10. What a transport has to provide

`AnchorCloud` is about forty lines over `NSUbiquitousKeyValueStore`. Any replacement has to
answer four things:

1. **A keyed store that lists by prefix.** Set, get and remove a JSON blob under a string key,
   and enumerate every key starting with `furlough.device.`, `furlough.revoke.`,
   `furlough.adds.`. Prefix listing is what lets the roster exist without a list two devices
   would have to agree on. Capacity: the whole store must hold one anchor record plus one
   entry, one possible revocation and one 20-deep ring per device.
2. **A reachability probe** that answers *"will anything actually cross"*, not *"is this
   configured"*. This distinction cost a day: `NSUbiquitousKeyValueStore.synchronize()` returned
   true on a Mac with iCloud Drive switched off while nothing crossed for half an hour, so the
   app cheerfully reported a link that did not exist. The probe now reads
   `FileManager.ubiquityIdentityToken`. A port needs a probe with the same property, and the
   answer has to be a **standing state** rather than a passing failure — a signed-out account
   does not resolve itself, and until it changes the devices are two separate installs that
   happen to look alike.
3. **A change signal**: something to observe so a device reads again when another writes,
   rather than polling. It must also be able to say when the *account itself* moved — signed
   in, signed out, or switched — because what arrives after that belongs to a different person
   than what came before, and both the probe and the record have to be read again.
4. **Identity scoping**: the store must already be scoped to one person, with no key of
   Furlough's own. Everything above assumes that a device reading `furlough.device.*` sees that
   person's devices and nobody else's.

**What iCloud gives for free, and what a relay would not.** The key-value store supplies all
four: Apple carries it under the user's own Apple Account, it works with the devices apart, and
the account *is* the identity, so there is no pairing step, no key exchange and no account of
Furlough's. A relay supplies (1) and (3) easily, (2) with care, and **not (4) at all**: without
the Apple Account there has to be a pairing step to establish that two devices belong to the
same person, and per-device keys so the relay cannot read what it carries.

That is not a small job, and it is not only an engineering job: it would mean Furlough running
a server, which the privacy page says it does not.

### What has no path today

**A device without iCloud has no path.** Not a slow one, not a degraded one — none. There is no
relay, there is no fallback transport, and nothing in this directory should be read as saying
one is coming or that it would be small.

---

## 11. The rules engine

Everything above is the *link*. This section is the other half: what Furlough decides on one
device, with nothing crossing at all. It is here because a port needs both — an Android build
that syncs the anchor perfectly and gets the windows wrong is not Furlough — and because the
engine is pure, so it is exactly the kind of thing a second implementation can be held to.

The vectors are in `fixtures/policy/`, 48 of them, named by what they exercise:
`status-`, `transition-`, `classify-`, `pending-`, `night-`, `week-`, `spans-`.

### Time, and the calendar

**Every vector is computed in one pinned calendar: Gregorian, GMT, `en_US_POSIX`, Sunday
first.** A port has to pin its own before comparing, because the minute of the day, the weekday
and the day boundary all move with the time zone.

Weekday numbers are Calendar's — **1 = Sunday … 7 = Saturday** — and `TimeWindow.days` numbers
its bits the same way, bit 0 for Sunday, so a weekday number and a bit position line up without
a conversion table. The bit sets a vector uses: 1 Sunday, 4 Tuesday, 62 Monday–Friday, 64
Saturday, 65 the weekend, 127 every day.

`now` is always **Furlough's own time**, never the device's wall clock. Every function that
takes one takes it as an argument; nothing in the engine reads a clock.

### Status — `Policy.status`

The one question the shields ask, answered in this order — the first that applies wins:

1. **`anchored`** — the anchor holds any of this target's doors at `now`. Read before the rule,
   always: an anchored target inside its open window is still anchored.
2. **`unconfigured`** — no rule. Nothing is enforced until the first rule is saved, and this
   status *is allowed*.
3. **`blockedAllDay`** — the rule allows no minute of any day.
4. **`exhausted(nextOpen)`** — today's budget is spent. Exhaustion is keyed by the day
   (`YYYY-MM-DD` in the pinned calendar), so yesterday's does not count.
5. **`open(until:)`** — inside a window. `until` is the window's end **as a minute counted from
   the start of today**, which is why it can exceed 1440 — see nights, below.
6. **`closed(nextOpen)`** — a window later today, else the next day that has one.

`nextOpen` is `{minuteOfDay, daysAhead}` where 0 is today and 7 is the same weekday next week.
The search runs `1...7` and wraps, so a Saturday looks into Sunday rather than running off the
end of the week; a rule with no windows reopens at `{0, 1}`, which is only the day rolling over
and its budget resetting.

Only `open` and `unconfigured` let the thing through. Every vector records that as `isAllowed`.

### The next transition — `Policy.nextTransition`

The next instant at which some status *can* change, over the whole config: the soonest window
edge later today — a start strictly after now, or an end after now and before midnight — else
the start of tomorrow. A timed anchor's `until` wins when it falls before that. An edge already
reached is not the next one: standing exactly on a window's start, the answer is its end.

### Tightening against loosening — `Policy.classify`

**Tightening lands at once; loosening waits out the delay.** That asymmetry is the whole
commitment device, so what counts as which is the most load-bearing rule in the engine.

For a rule: `new.isTighterOrEqual(to: old)`, where a missing rule on either side reads as
*unrestricted* — every minute allowed, a full day of budget. So a target's first rule is always
a tightening, and removing a rule is always a loosening. "Tighter or equal" is checked **day by
day, for all seven days**: no minute allowed that the old rule forbade, and no larger budget on
any day. Two hours moved off Sunday onto Monday leaves the week the same size and Monday
looser — and a looser Monday is a loosening. Equal is a tightening: writing one budget out as
seven equal ones changes no day, so nothing queues.

For a tier, the comparison is the **delay it buys**, not what it allows: a tier changes nothing
about what is blocked, only how long the next loosening waits. Moving toward hazard lengthens
the wait and lands now; moving toward essential shortens it and queues, which is what stops
"mark everything essential" from being a way out of the delay.

### Pending changes landing — `Policy.applyDuePending`

Everything whose `effectiveAt <= now` — the comparison is `<=`, so a change due at this very
instant lands — applied **in `effectiveAt` order**, then removed from the queue. A change whose
target no longer exists applies to nothing and is still spent and counted.

Two things a port could implement halfway and still pass a naive test:

- **The undo window is expired here too**, before anything else, and on its own makes the pass
  report a change. An undo closing is a change coming due like any other rather than something
  compared against the clock on every read.
- **This is the one place a landing is counted into the record.** The vectors carry
  `landedToday` for that reason.

### A window crossing midnight

A stored window never crosses midnight. A night is written as two: an evening ending at 1440 on
the days it starts, and a morning starting at 0 on **the days after** — the bit set shifted one
day on, so a Saturday night's morning half is a Sunday. An evening that runs to exactly midnight
has no morning half and splits into itself.

`folded` is the exact inverse, not a guess: those two windows and that one night allow the very
same minutes of the week, so a night reads back as the row it was written as.

And it is **one window to whoever is using it**, so nothing shuts at the join and nothing says
it does: inside the evening half, the status reports the morning it really ends — 1680 for a
5 PM to 4 AM night. Unless the morning is worth no minutes, in which case there is no morning
half to run into and the night really does end at 1440.

### Per-weekday budgets

A rule carries either one `dailyBudgetMinutes` or seven `budgetByWeekday`, Sunday first. **Every
read goes through one accessor**, which answers the single number seven times over when there is
no array — so nothing downstream ever has to know which kind of rule it is holding.

The rule that catches people out: **a day worth no minutes has no open hours at all.** Its
windows are not offered, the status reads closed from the hours alone, and the next-open search
skips it. That is also why a Saturday night stops at midnight when the Sunday is worth nothing.

Saving normalises: seven equal days say nothing the one number does not, so the array is dropped
and the single figure is replaced with what the week actually said. Underneath a real
per-weekday budget, `dailyBudgetMinutes` is a shadow that can be any figure at all — which is
why an editor collapsing seven sliders back to one is offered the *representative* budget, the
figure most days already carry, and the smaller of two that tie.

### Spans — `ActivityLimit.spans`

**A caveat before the vectors.** The *ceiling* here is Apple's: iOS allows 20 DeviceActivity
activities, one is the daily budget tracker, so 19 window spans is the limit and the phone's
editor refuses a rule past it while it is still a draft. A port has its own scheduler and its
own ceiling, or none, and should not inherit that number.

What does carry over is the **decomposition**, which is a property of the rule set rather than
of Apple: the distinct spans a config asks to be watched are every window of every saved rule
*and every queued one*, with the days stripped, and nothing at all from a rule that never allows
anything. The same hours on different days are one span — the scheduler is told about hours and
the engine decides the day. A queued loosening sits *beside* the rule it will replace rather
than instead of it, so both sets of hours are live at once; counting only the new rule would let
exactly the edit that overflows through.

Per-weekday budgets do not press on this at all: a budget is an event carried by the day
activity, not an activity of its own.

### What these vectors do not cover

Named so nobody mistakes the set for the whole engine:

- **`Policy.decide`** — the projection of every status onto what a platform actually blocks. It
  is genuinely two functions, one per platform, because an iOS shield takes Screen Time tokens
  and the Mac's takes bundle identifiers and hosts. A port writes its own, and the statuses
  above are its input.
- **`Policy.summary`** — what a widget and a Live Activity read. Presentation.
- **The record** (`Record.swift`) — what happened, counted for two screens. Never read by
  anything that decides what is blocked, which is the point of it.
- **The delay arithmetic** (`Config.delayHours`) — how long a loosening waits, given a tier.
  `classify` above decides *whether* something waits; this decides *how long*, and it is a
  small enough sum to read off the tier's multiplier in `tables/tiers.json`.

---

## 12. The tables

`tables/` is the part of Furlough that is knowledge rather than logic: which things are the
same thing under two names, what each is worth, and what rule to start it on. All of it is
offline and exact, so a port loads these rather than re-deriving them — and three of the four
are dumped straight from the Swift by the same test that checks the fixtures, so they cannot
drift either.

| File | From | Holds |
| --- | --- | --- |
| `companions.json` | `Companions.pairs` | 83 pairs, in table order: `title` (the first name, what to call it), every `names` it is written as, every `bundleIDs` it ships under on either Apple platform, and the `hosts` it lives at. Names match case- and space-insensitively; hosts match subdomains, longest rule first. |
| `tiers.json` | `AppUtility` | What a thing is worth, keyed four ways: `names` (152), `bundleIDs` (133), `bundleIDPrefixes` (13, matched exactly or up to a dot, longest wins) and `hosts` (98, subdomains count, longest wins). Each row is a `utility` of essential/useful/idle/hazard, and a `detail` on the essentials, where saying the specific harm beats the generic line. |
| `rule-suggestions.json` | `RuleSuggestion` | The 30 per-app exceptions to what a tier alone suggests, with the tier each was written against. A row carries `budgetMinutes` and an optional `window`. These are **judgements, not facts** — retunable any afternoon — which is why they are a separate table from the tiers. |
| `other-platforms.json` | hand-filled | What each companion pair is called on Android and Windows. All 83 `android` arrays are filled but one, each confirmed against its own Play listing; `windows` is empty throughout and still undecided. See [Not decided](#not-decided). |

Two things a tier table is **not**: it never blocks anything, and it never applies anything.
It is offered and argued with in an editor, and the engine that decides what is shielded has
never read it.

---

## Not decided

Open questions. None of these is described above as if it were settled, and none should be
built without asking Zach.

- **The relay.** See §10. Everything non-Apple depends on it, and it is the decision, not the
  implementation.
- **`canRelease` in the merge.** `merge` accepts a release only from `origin == tagScan` **and**
  `platform == phone`. The roster already carries `canRelease` per device, and switching the
  merge to read it is a one-line change that has not been made. Today the two agree — a phone
  is exactly what has a reader — so nothing observable turns on it. It would matter the moment
  a platform has readers on some devices and not others, which is where Android lands.
- **Platform values beyond `phone`, `pad` and `mac`.** Adding one is not free: an older build
  reading an unknown platform drops the whole entry (§3), so a device on a new platform is
  invisible to every device that has not been updated. What that should do — and whether it
  wants a version field the current record has no room for — is unanswered.
- **Whether extensions may write the store.** Open since the Anchor first crossed. Today the
  roster and the rings are only ever written by the apps.
- **`tables/other-platforms.json`, the `windows` column.** Windows executables per companion
  pair, still shipped with no values. The house rule is that every entry is confirmed from a
  vendor source, and most Windows executables cannot be confirmed from a vendor page at all, so
  that column would stay largely empty however much work went into it. What would count as a
  confirmation there is the undecided part, and until it is decided nothing is guessed.

  The `android` column was the same decision until **2026-09-11**, when Zach asked for the
  groundwork a Kotlin port needs before the port itself exists, which is what it is for. It is
  now filled for 82 of the 83 pairs. Each was confirmed against its own listing at
  `https://play.google.com/store/apps/details?id=<package>`, which had to answer 200 *and* name
  the app in its `og:title` — a 200 alone only proves some app owns that identifier, not the
  right one. `theScore Bet` is the one left empty: its sportsbook left the US and the remaining
  listing is regional, and the neighbouring theScore news app is a different product, so
  standing it in would be exactly the guess the rule forbids. Anything that cannot be confirmed
  stays empty.

---

## Using the fixtures

Every file is `{ "name", "function", "input", "expected" }`. `function` names the Swift
function the vector exercises, so the folders are organisation and the field is the contract.

There are 90. The link: 11 for `merge`, 6 for `macDrop`, 9 for the roster, 16 for the ring, the
watermark and the landing. The engine, all in `policy/` and named by their prefix: 13 for
`status` (two of them nights), 6 for `nextTransition`, 12 for `classify`, 6 for
`applyDuePending`, 3 for splitting and folding a night, 5 for a week of budgets, 3 for spans.

Inputs are **written by hand** and use fixed ISO-8601 dates, never a clock. Expectations are
**written by the code**: run the test with `FURLOUGH_WRITE_FIXTURES=1` in the test process's
environment and every `expected` is rewritten from the current behaviour instead of asserted.
So a change in behaviour fails the test until someone regenerates on purpose, and the diff of
these files is the review.

To check them:

```bash
xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

To regenerate them. The `TEST_RUNNER_` prefix is how a variable reaches the test process —
`xcodebuild` does not hand its own environment to the runner, and without the prefix the flag
is silently ignored and the run simply asserts:

```bash
TEST_RUNNER_FURLOUGH_WRITE_FIXTURES=1 xcodebuild test -project Furlough.xcodeproj -scheme FurloughCoreTests -destination 'platform=macOS,arch=arm64'
```

The same run checks `tables/` against the Swift tables and each `schema/` file against a real
encode: every key the encoder writes must be a property the schema names, and each enum's raw
values must equal the schema's `enum` list.

Three notes for a second implementation:

- **The expectations are projections, not whole objects, where the whole object would be
  noise.** `appended` is checked by the resulting ring's ids and sequences in order, because
  that is all it decides; it never alters an entry's contents. `unseen` is checked by
  `{origin, sequence, title}` in order. `merge`, `macDrop` and `applyDuePending` are checked by
  the whole thing they produce, because there is no projection of it that would be less than
  the thing itself.
- **Inputs are minimal, and that is legitimate.** `Config`, `AnchorProfile`, `Rule` and
  `RuntimeState` all have tolerant decoders, so a fixture writes only the fields the case is
  about and everything else takes its default. A port's own reader must be equally tolerant:
  `"runtime": {}` is a real, valid runtime.
- **Pin the calendar before comparing anything under `policy/`.** Gregorian, GMT,
  `en_US_POSIX`, Sunday first, weekday numbers 1…7 with 1 = Sunday. Run these against a local
  time zone and roughly half of them will disagree for reasons that have nothing to do with the
  engine.
