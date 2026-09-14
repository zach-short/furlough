// The few facts the pages need. Everything else is copy.
export const site = {
  name: 'Furlough',
  tagline: 'App blocker with no unblock button, and a lock only an NFC tag lifts.',
  description:
    'Two ways to put an app out of reach. Give apps a daily budget and the hours they are allowed, where the only way to loosen a rule is to wait — or anchor the phone in one tap, and lift it only by holding it to an NFC tag you paired.',
  // Set this once the App Store record exists. Until then the download button says so.
  appStoreURL: null as string | null,
  githubURL: 'https://github.com/zach-short/furlough',
  // The notarized Developer ID build. Bump the filename (and this path) each time
  // scripts/archive-mac.sh cuts a new one — public/downloads/ keeps only the latest.
  macDownloadURL: '/downloads/Furlough-1.2.0.dmg',
  macVersion: '1.2.0',
  // Cloudflare Email Routing forwards this to the real inbox — domain address, not personal.
  email: 'support@furloughapp.com',
  author: 'Zach Short',
  policyUpdated: '8 September 2026',
};
