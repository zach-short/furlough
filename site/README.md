# Furlough site

The landing page for the app, plus the privacy policy and support pages the App Store asks for.
Static HTML built with [Astro](https://astro.build); the only JavaScript on the page is the
animation: the living hourglass, the ember that laps the wall, and the scroll reveals.

It wears the app's own look. `src/styles/global.css` carries the Ember Glass tokens from
`design/DESIGN.md`, the three typefaces are the app's, subset to `woff2` in `public/fonts`
(OFL licences alongside), and `src/lib/hourglass.ts` is a port of
`Shared/UI/HourglassGeometry.swift` and `Hourglass.swift` to a canvas, so the glass on the
web is the glass on the phone. Keep the tokens in step with `Shared/UI/Theme.swift`.

```bash
bun install
bun run dev      # http://localhost:4321
bun run build    # dist/, static
bun run preview
```

## Before it ships

- `appStoreURL` in `src/site.ts`: the App Store link. Until it is set the download buttons
  read "Coming soon to the App Store" and are not links.
- `site` in `astro.config.mjs` is the public origin (`https://furloughapp.com`). The canonical
  link and the Open Graph image are built from it.

It is served by Cloudflare Pages, project `furlough`, which owns `furloughapp.com` and
`furlough-4e1.pages.dev`. Deploys are direct uploads with wrangler, not git-linked:

```bash
bun run deploy   # astro build, then wrangler pages deploy dist --project-name furlough
```

Pages serves `privacy/index.html` at `/privacy/` and redirects `/privacy` to it, which is why
the site links and canonicals carry the slash while the App Store fields may stay slashless.

## Pages

| Path | What |
|---|---|
| `/` | The pitch: hero with the app's Home screen running a demo evening, budgets, windows, the delay, the Anchor, the shield, every hourglass status, privacy, the way out, download. |
| `/privacy` | The privacy policy. Same words as `design/store/privacy.html`. |
| `/support` | Support. Same words as `design/store/support.html`, plus the Mac note. |

## Checking it

The in-app Browser pane keeps its document hidden, so `requestAnimationFrame` never fires
there and nothing animated runs. Headless Chrome renders frames; from the repo root:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --user-data-dir=/tmp/furlough-shots --no-first-run --disable-gpu --hide-scrollbars \
  --window-size=1440,5600 --virtual-time-budget=8000 --screenshot=/tmp/site.png http://localhost:4321/
```

It will not lay out narrower than about 540 px, so check phone widths with device emulation
in a real browser instead.
