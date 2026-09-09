// @ts-check
import { defineConfig } from 'astro/config';

// Static site: every page is plain HTML with only the animation scripts on top.
// Pages build to directories (privacy/index.html), so /privacy works on any host.
export default defineConfig({
  // The public origin. Without it `Astro.site` is undefined, `Base.astro` emits no
  // canonical link at all, and og:image resolves against a build-time URL rather than
  // the real host.
  site: 'https://furloughapp.com',
  output: 'static',
});
