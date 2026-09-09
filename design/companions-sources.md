# Where the companion pairs came from

The audit trail for `Companions.pairs` in `Shared/Core/Companions.swift`. Every row below was
confirmed by an App Store lookup actually run on 2026-09-09, not from memory:

```bash
curl -s "https://itunes.apple.com/search?term=duolingo&entity=software&country=us&limit=5" \
  | python3 -c "import json,sys; [print(r['trackName'],'|',r['bundleId'],'|',r.get('sellerUrl')) for r in json.load(sys.stdin)['results']]"
```

**Read this before adding a pair.** A wrong bundle identifier makes the offer never appear,
which is invisible and will not be noticed for months. A wrong host is worse: Furlough would
offer to block a domain that is not the thing, and someone would accept it and lose access to
something they never meant to shut. Confirmed beats remembered, every time.

Two rules the table enforces in tests (`Tests/Core/CompanionsTests.swift`), both learned here:

- **Identifiers are lowercased in the table.** `Pair.matches` normalizes the identifier it is
  *handed* but compares it against the table as written, so a capital letter is an entry that can
  never match anything. Apple returns `net.whatsapp.WhatsApp`; the table says `net.whatsapp.whatsapp`.
- **No two pairs claim the same host.** `pair(forHost:)` answers with the longest match, so a
  subdomain deliberately beats a domain — `music.youtube.com` is YouTube Music even though YouTube
  claims `youtube.com`. That is the only legal overlap.

The **Seller URL** column is the evidence: where its registrable domain matches the host, the pair
is confirmed outright. Four rows below could not be confirmed that way and carry a note saying what
the second confirmation was.

## The 50 pairs added 2026-09-09

| Pair | App Store name | Bundle ID (as Apple returns it) | Seller | Host | Seller URL | Listing |
|---|---|---|---|---|---|---|
| Peacock TV | Peacock TV: Stream TV & Movies | `com.peacocktv.peacock` | Peacock TV LLC | `peacocktv.com` | https://www.peacocktv.com/ | https://apps.apple.com/us/app/peacock-tv-stream-tv-movies/id1508186374 |
| Paramount+ | Paramount+ | `com.cbsvideo.app` | CBS Interactive | `paramountplus.com` | https://www.paramountplus.com/ | https://apps.apple.com/us/app/paramount/id530168168 |
| Crunchyroll | Crunchyroll | `com.crunchyroll.iphone` | Crunchyroll, LLC | `crunchyroll.com` | https://www.crunchyroll.com/ | https://apps.apple.com/us/app/crunchyroll/id329913454 |
| Rumble | Rumble: Live Streaming, Videos | `com.rumble.battles` | Rumble Inc. | `rumble.com` | https://rumble.com/ | https://apps.apple.com/us/app/rumble-live-streaming-videos/id1518427877 |
| Kick | KICK - Live Streaming | `com.kick.mobile` | Kick Streaming | `kick.com` | https://www.kick.com | https://apps.apple.com/us/app/kick-live-streaming/id6446202561 |
| Quora | Quora | `com.quora.app.mobile` | Quora, Inc. | `quora.com` | https://www.quora.com | https://apps.apple.com/us/app/quora/id456034437 |
| Nextdoor | Nextdoor: Neighborhood Network | `com.nextdoor.nextdoor` | Nextdoor | `nextdoor.com` | https://www.nextdoor.com | https://apps.apple.com/us/app/nextdoor-neighborhood-network/id640360962 |
| BeReal | BeReal: Photos & Friends Daily | `AlexisBarreyat.BeReal` | BeReal | `bereal.com` | https://bereal.com | https://apps.apple.com/us/app/bereal-photos-friends-daily/id1459645446 |
| Canva | Canva AI Photo & Video Editor | `com.canva.canvaeditor` | Canva | `canva.com` | https://www.canva.com/download/ios/ | https://apps.apple.com/us/app/canva-ai-photo-video-editor/id897446215 |
| Trello | Trello: Daily Task Tracker | `com.fogcreek.trello` | Trello, Inc. | `trello.com` | https://trello.com/ | https://apps.apple.com/us/app/trello-daily-task-tracker/id461504587 |
| Trello (Mac) | Trello | `com.atlassian.trello` | Trello, Inc. | `trello.com` | https://trello.com/ | https://apps.apple.com/us/app/trello/id1278508951 |
| Substack | Substack | `com.substack.Substack` | Substack, Inc. | `substack.com` | https://substack.com/ | https://apps.apple.com/us/app/substack/id1581650857 |
| Medium | Medium: Read & Write Stories | `com.medium.reader` | A Medium Corporation | `medium.com` | https://about.medium.com/ | https://apps.apple.com/us/app/medium-read-write-stories/id828256236 |
| Duolingo | Duolingo: Language Lessons | `com.duolingo.DuolingoMobile` | Duolingo | `duolingo.com` | https://www.duolingo.com | https://apps.apple.com/us/app/duolingo-language-lessons/id570060128 |
| Claude | Claude by Anthropic | `com.anthropic.claude` | Anthropic PBC | `claude.ai` | https://claude.ai | https://apps.apple.com/us/app/claude-by-anthropic/id6473753684 |
| Gemini | Google Gemini | `com.google.gemini` | Google | `gemini.google.com` | https://gemini.google.com/app/download | https://apps.apple.com/us/app/google-gemini/id6477489729 |
| Perplexity | Perplexity - AI Search & Chat | `ai.perplexity.app` | Perplexity AI, Inc. | `perplexity.ai` | https://www.perplexity.ai/iphone | https://apps.apple.com/us/app/perplexity-ai-search-chat/id1668000334 |
| Character.AI | Character AI: Chat, Talk, Text | `ai.character.app` | Character.AI | `character.ai` | https://character.ai/ | https://apps.apple.com/us/app/character-ai-chat-talk-text/id1671705818 |
| Grok | Grok AI | `ai.x.GrokApp` | X Corp. | `grok.com` | https://x.ai/ | https://apps.apple.com/us/app/grok-ai/id6670324846 |
| SoundCloud | SoundCloud: The Music You Love | `com.soundcloud.TouchApp` | SoundCloud Global Limited & Co KG | `soundcloud.com` | http://soundcloud.com/mobile | https://apps.apple.com/us/app/soundcloud-the-music-you-love/id336353151 |
| Pandora | Pandora: Music & Podcasts | `com.pandora` | Pandora Media, LLC | `pandora.com` | http://www.pandora.com/ | https://apps.apple.com/us/app/pandora-music-podcasts/id284035177 |
| TIDAL | TIDAL Music: HiFi Sound | `com.aspiro.TIDAL` | TIDAL Music AS | `tidal.com` | http://tidal.com | https://apps.apple.com/us/app/tidal-music-hifi-sound/id913943275 |
| ESPN | ESPN: Live Sports & Scores | `com.espn.ScoreCenter` | Disney | `espn.com` | http://www.espn.com/ | https://apps.apple.com/us/app/espn-live-sports-scores/id317469184 |
| NFL | NFL | `com.nfl.gamecenter` | NFL Enterprises LLC | `nfl.com` | http://www.nfl.com/mobile/app | https://apps.apple.com/us/app/nfl/id389781154 |
| Bleacher Report | Bleacher Report: Sports News | `com.bleacherreport.TeamStream` | Bleacher Report | `bleacherreport.com` | http://bleacherreport.com/mobile | https://apps.apple.com/us/app/bleacher-report-sports-news/id418075935 |
| CNN | CNN: Live & Breaking News | `com.cnn.iphone` | CNN Interactive Group, Inc. | `cnn.com` | https://www.cnn.com/app | https://apps.apple.com/us/app/cnn-live-breaking-news/id331786748 |
| FOX News | FOX News: US & World Headlines | `com.foxnews.foxnews` | Fox News Network, LLC | `foxnews.com` | https://www.foxnews.com | https://apps.apple.com/us/app/fox-news-us-world-headlines/id367623543 |
| NYTimes | NYTimes: US and Global News | `com.nytimes.NYTimes` | The New York Times Company | `nytimes.com` | http://www.nytimes.com/services/mobile/apps/ | https://apps.apple.com/us/app/nytimes-us-and-global-news/id284862083 |
| Tinder | Tinder Dating App: Date & Chat | `com.cardify.tinder` | Tinder LLC | `tinder.com` | https://tinder.com | https://apps.apple.com/us/app/tinder-dating-app-date-chat/id547702041 |
| Bumble | Bumble Dating App: Meet & Date | `com.moxco.bumble` | Bumble Holding Limited | `bumble.com` | http://bumble.com/ | https://apps.apple.com/us/app/bumble-dating-app-meet-date/id930441707 |
| Hinge | Hinge Dating App: Match & Date | `co.hinge.mobile.ios` | Hinge, Inc. | `hinge.co` | http://hinge.co | https://apps.apple.com/us/app/hinge-dating-app-match-date/id595287172 |
| Grindr | Grindr - Gay Dating & Chat | `com.grindrguy.grindrx` | Grindr LLC | `grindr.com` | https://www.grindr.com | https://apps.apple.com/us/app/grindr-gay-dating-chat/id319881193 |
| OkCupid | OkCupid Dating: Date Singles | `com.okcupid.app` | Match Group Americas, LLC | `okcupid.com` | http://www.okcupid.com | https://apps.apple.com/us/app/okcupid-dating-date-singles/id338701294 |
| BetMGM | BetMGM - Sportsbook & Casino | `com.playmgm.nj.sports2` | BetMGM | `betmgm.com` | https://sports.nj.betmgm.com/en/sports | https://apps.apple.com/us/app/betmgm-sportsbook-casino/id1430875409 |
| PrizePicks | PrizePicks - Sports Picks | `com.myprizepicks.prizepicks` | SidePrize, LLC | `prizepicks.com` | https://www.prizepicks.com | https://apps.apple.com/us/app/prizepicks-sports-picks/id1437843273 |
| Underdog | Underdog Sports | `com.underdogsports.fantasy` | Underdog Sports, Inc. | `underdogfantasy.com` | https://www.underdogfantasy.com | https://apps.apple.com/us/app/underdog-sports/id1514665962 |
| theScore Bet | theScore Bet Sportsbook Casino | `com.espn.bet` | Score Media and Gaming Inc. | `thescore.bet` | https://www.thescore.bet/ | https://apps.apple.com/us/app/thescore-bet-sportsbook-casino/id6463805689 |
| Roblox | Roblox | `com.roblox.robloxmobile` | Roblox Corporation | `roblox.com` | http://www.roblox.com/ | https://apps.apple.com/us/app/roblox/id431946152 |
| Chess.com | Chess.com - Play and Learn | `com.chess.iphone` | Chess.com | `chess.com` | https://www.chess.com | https://apps.apple.com/us/app/chess-com-play-and-learn/id329218549 |
| Lichess | Lichess | `org.lichess.mobileV2` | LICHESS.ORG | `lichess.org` | None | https://apps.apple.com/us/app/lichess/id1662361230 |
| eBay | eBay online shopping & selling | `com.ebay.iphone` | eBay Inc. | `ebay.com` | http://www.ebay.com/ | https://apps.apple.com/us/app/ebay-online-shopping-selling/id282614216 |
| Etsy | Etsy: Shop from Real People | `com.etsy.etsyforios` | Etsy, Inc. | `etsy.com` | https://www.etsy.com/mobile | https://apps.apple.com/us/app/etsy-shop-from-real-people/id477128284 |
| Temu | Temu: Shop Like a Billionaire | `com.einnovation.temu` | Temu | `temu.com` | None | https://apps.apple.com/us/app/temu-shop-like-a-billionaire/id1641486558 |
| SHEIN | SHEIN - Shopping Online | `zzkko.com.ZZKKO` | ROADGET BUSINESS PTE. LTD. | `shein.com` | https://www.shein.com | https://apps.apple.com/us/app/shein-shopping-online/id878577184 |
| Walmart | Walmart: Shopping & Savings | `com.walmart.electronics` | Walmart | `walmart.com` | http://www.walmart.com/cp/Walmart-Mobile-App/1087865#appleiOS | https://apps.apple.com/us/app/walmart-shopping-savings/id338137227 |
| Target | Target: Shop. Style. Save. | `com.target.Target` | Target | `target.com` | https://www.target.com/c/target-app/-/N-4th2r | https://apps.apple.com/us/app/target-shop-style-save/id297430070 |
| Poshmark | Poshmark: Shop & Sell Fashion | `com.poshmark.poshmark` | Poshmark, Inc. | `poshmark.com` | http://poshmark.com | https://apps.apple.com/us/app/poshmark-shop-sell-fashion/id470412147 |
| StockX | StockX - Sneakers and Apparel | `com.Campless.Campless` | StockX LLC | `stockx.com` | https://stockx.com | https://apps.apple.com/us/app/stockx-sneakers-and-apparel/id881599819 |
| Depop | Depop - Buy & Sell Clothes | `com.garageitaly.garage` | Depop Ltd | `depop.com` | http://www.depop.com | https://apps.apple.com/us/app/depop-buy-sell-clothes/id518684914 |
| AliExpress | AliExpress - Shopping App | `com.alibaba.iAliexpress` | Alibaba | `aliexpress.com` | http://www.aliexpress.com | https://apps.apple.com/us/app/aliexpress-shopping-app/id436672029 |
| craigslist | craigslist | `org.craigslist.CraigslistMobile` | craigslist | `craigslist.org` | None | https://apps.apple.com/us/app/craigslist/id1336642410 |

## The four that needed a second confirmation

Apple returned no `sellerUrl` for these (or one on a different domain), so the host was confirmed
by fetching it and reading what it served, on 2026-09-09:

| Pair | Why the seller URL was not enough | Second confirmation |
|---|---|---|
| Temu | `sellerUrl` was null | `https://temu.com` served `<title>Temu \| Explore the Latest Clothing, Beauty, Home, Jewelry & More</title>` |
| craigslist | `sellerUrl` was null | `https://craigslist.org` served `<title>craigslist: richmond, VA jobs, apartments, for sale, services, community, and events</title>`; the App Store seller is literally `craigslist` |
| Lichess | `sellerUrl` was null | `https://lichess.org` served `<title>lichess.org • Free Online Chess</title>`; the App Store seller is literally `LICHESS.ORG` |
| Grok | `sellerUrl` is `https://x.ai/`, the company site, not the product's | `https://grok.com` served `<title>Grok</title>` |

## Rejected, and why

Kept here so the next session does not spend the lookups again.

| Candidate | Why it did not go in |
|---|---|
| Mercari | `sellerUrl` null, and `https://mercari.com` answered with a Cloudflare interstitial (`<title>Just a moment...</title>`) rather than anything identifying Mercari. Nothing confirmed the host. |
| ESPN BET | The bundle `com.espn.bet` now returns **theScore Bet Sportsbook Casino**, seller *Score Media and Gaming*, `sellerUrl` `thescore.bet` — the product was rebranded. `espnbet.com` is confirmed by nothing, so it is not in the table; the pair went in as **theScore Bet** against the host its own seller URL names. |
| Microsoft Copilot | Apple returns bundle `com.microsoft.officemobile` — the Office app, rebranded — with `sellerUrl` `products.office.com`. One identifier for two products, and nothing confirming `copilot.microsoft.com`. |
| The Athletic | `sellerUrl` is `https://www.nytimes.com/athletic/`, whose registrable domain is `nytimes.com`, not `theathletic.com`. NYT owns it, which is exactly why the seller URL cannot confirm the host. |
| Apple TV, Apple Music | `sellerUrl` null or `apple.com`. `apple.com` is banned by the table's own rule, and nothing confirmed `tv.apple.com` / `music.apple.com`. |
| Airbnb, Yelp | Both confirm cleanly (`com.airbnb.app`/`airbnb.com`, `com.yelp.yelpiphone`/`yelp.com`). Left out on the table's other rule — *do not add things nobody blocks* — rather than on evidence. Add them the day somebody wants them. |
| Fubo, Pluto TV, Vimeo, Dailymotion, Letterboxd, Goodreads, Strava, NewsBreak | All confirmed by lookup, all trimmed to keep the addition at the 50 the task asked for. The confirmations are in this session's transcript; they are the first things to reach for next time. |
