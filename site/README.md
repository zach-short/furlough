# Furlough site

The website at [furloughapp.com](https://furloughapp.com): the landing page, a page for the Mac download, help pages, the release history, and the privacy policy and support pages that the App Store listing links to. It is static HTML built with [Astro](https://astro.build) 7. The JavaScript on a page runs the animation (the living hourglass, the ember that laps the wall, the scroll reveals), the demos on the home page that behave like the app's own controls, and a short inline script in `src/layouts/Base.astro` that detects a Mac so the Mac download leads for Mac visitors.

It wears the app's own look. `src/styles/global.css` carries the Ember Glass tokens from `design/DESIGN.md`, the three typefaces are the app's, subset to `woff2` in `public/fonts` (OFL licences alongside), and `src/lib/hourglass.ts` is a port of `Shared/UI/HourglassGeometry.swift` and `Hourglass.swift` to a canvas, so the glass on the web is the glass on the phone. Keep the tokens in step with `Shared/UI/Theme.swift`.

## Running it

Use bun, never npm. The lockfile is `bun.lock` and there is no `package-lock.json`. Astro 7 needs Node 22.12 or later.

```bash
bun install
bun run dev      # http://localhost:4321
bun run build    # dist/, static
bun run preview
```

The package has no test suite and no linter. A clean `bun run build` shows that the pages compile, and the rest is checked by looking at them (see [Checking it](#checking-it)). The build also reads `../release-notes.json` from the repository root, so the site builds only inside a full checkout.

## Layout

| Path | What it holds |
|---|---|
| `src/site.ts` | The few facts the pages share: the store link, the Mac download, the support address, the policy date. |
| `src/layouts/Base.astro` | The head tags, canonical link, Open Graph tags, Mac detection, and the three animation scripts. |
| `src/components/` | `Nav`, `Footer`, `StoreButton`, and `HeroPage`, the phone-shaped demo at the top of the home page. |
| `src/lib/` | `hourglass.ts` (the glass), `wall.ts` (the ember behind the page), `reveal.ts` (scroll reveals). |
| `src/pages/` | One file per route. |
| `src/styles/global.css` | Tokens, type, the glass buttons, and the platform swap. |
| `public/` | Fonts, icons, `noise.png`, `downloads/` (the Mac disk image) and `review/` (the App Review video). |

The platform swap is a pair of classes. `Base.astro` adds `is-mac` to the `html` element before the body paints, and `global.css` then hides `.only-ios` or `.only-mac` content. The App Store listing is the iPhone build, so on a Mac the loudest link on each page points at the Mac download instead.

## Configuration

`site` in `astro.config.mjs` is the public origin, `https://furloughapp.com`. Without it the pages carry no canonical link and the Open Graph image resolves against a build-time URL.

The rest lives in `src/site.ts`:

- `appStoreURL` is the App Store link. Set it to `null` and the download buttons read "Coming soon to the App Store" and stop being links.
- `macDownloadURL` and `macVersion` name the Mac disk image that `/mac/` offers.
- `macMinimumOS` is stated on `/mac/` and matches the macOS deployment target in `project.yml`.
- `policyUpdated` is the date printed on the privacy policy. Change it whenever the policy text changes.
- `email` is the support address. Cloudflare Email Routing forwards it to the real inbox.

`src/pages/releases.astro` imports `release-notes.json` from the repository root, the same file both apps bundle. A version added there reaches the site at the next deploy, with no second copy to update.

## Deploying

The site is served by Cloudflare Pages, project `furlough`, which owns `furloughapp.com` and `furlough-4e1.pages.dev`. Deploys are direct uploads with wrangler, not git-linked, so a change reaches the public site only when someone runs the deploy. Wrangler is not a dependency of this package. The script calls whichever `wrangler` is on the path, and it must be logged in to the Cloudflare account that owns the project.

```bash
bun run deploy   # astro build, then wrangler pages deploy dist --project-name furlough --commit-dirty=true
```

From the repository root, `scripts/furlough deploy` runs the same thing.

Pages serves `privacy/index.html` at `/privacy/` and redirects `/privacy` to it. This is why the site links and canonicals carry the trailing slash while the App Store fields may stay slashless.

Astro builds `src/pages/404.astro` to `dist/404.html`, which Pages serves with a real 404 status. Without that file, a mistyped URL would answer 200 with the home page.

### Publishing a new Mac build

1. From the repository root, run `scripts/archive-mac.sh` (or `scripts/furlough mac-release`). It writes `build/mac-release/Furlough-<version>.dmg`.
2. Copy that file into `public/downloads/` and delete the older image. The folder keeps only the latest.
3. Set `macDownloadURL` and `macVersion` in `src/site.ts`.
4. Deploy.

## Pages

| Path | What |
|---|---|
| `/` | The pitch: the hero with the app's Home screen running a demo evening, the two halves (rules and the Anchor), budgets, windows, the delay, the shield, every hourglass status, privacy and the way out, and the download. |
| `/mac/` | The Mac download, why it is not on the Mac App Store, and what macOS will ask for. |
| `/help/` | The index of help topics. Eight pages sit under it: windows and budgets, apps and websites, apps the picker will not show, the Anchor, NFC tags, automations, outside the app, and about. |
| `/releases/` | The release history, rendered from `release-notes.json`. |
| `/privacy/` | The privacy policy. |
| `/support/` | Support, including the one way out and what to do when a shield seems stuck. |
| `/review/anchor/` | The NFC demo video for App Review. It is unlisted, marked `noindex`, and linked from nowhere on the site. |

The privacy and support pages here are the current text, and the store listing points at them. The HTML copies in `design/store/` are older and differ from them, so edit the pages in this folder.

## Checking it

The in-app Browser pane keeps its document hidden, so `requestAnimationFrame` never fires there and nothing animated runs. Headless Chrome renders frames. From the repo root, with the dev server running:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --user-data-dir=/tmp/furlough-shots --no-first-run --disable-gpu --hide-scrollbars \
  --window-size=1440,5600 --virtual-time-budget=8000 --screenshot=/tmp/site.png http://localhost:4321/
```

It will not lay out narrower than about 540 px, so check phone widths with device emulation in a real browser instead.
