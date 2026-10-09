# Website event counts

Events: `install_click` (hero/nav/hero_download/install_download/download), `install_copy` (only after clipboard write succeeds), `source_click` (header/hero/footer). Store UTC daily counts grouped by event, button position and page language. These are action counts, not unique visitors, completed downloads or installations. Repeated clicks count again; blockers/network failures can undercount and scripted requests can inflate totals. DNT/GPC users and deployment-preview hosts are excluded. Cloudflare's infrastructure may process request metadata; the application stores no IPs, user IDs, clipboard text or full URLs.

## Local verification

Run from repository root:

```sh
npx wrangler d1 execute codex-usage-events-local --local --file analytics/schema.sql
npx wrangler pages dev docs --port 8772 --d1 ANALYTICS_DB=00000000-0000-0000-0000-000000000000
```

## Production (requires release approval)

1. Create D1 database `codex-usage-events` using `wrangler d1 create codex-usage-events`.
2. Update root `wrangler.jsonc` with `name: codex-usage`, `pages_build_output_dir: docs`, `compatibility_date: 2026-10-04` and a `d1_databases` entry containing binding `ANALYTICS_DB`, database name and the real returned database ID. Never use the local test ID for deployment.
3. Apply schema: `npx wrangler d1 execute codex-usage-events --remote --file analytics/schema.sql`.
4. From repository root deploy: `npx wrangler pages deploy docs --project-name codex-usage --branch main`. The root `functions/` directory must be included. Do not deploy the `docs/` folder alone from `/tmp`.
5. Verify a normal browser click reaches `/api/events` with 204 and query the database for the corresponding aggregate. Record the before/after count for the single acceptance click; it is a real requested download click and remains in that aggregate.

## View counts

Cloudflare Dashboard → Storage & databases → D1 → codex-usage-events → Console. Alternatively run `npx wrangler d1 execute codex-usage-events --remote --file analytics/report.sql` from repository root.

There is no public read API. Counts require account access. To roll back, restore the previous Pages deployment `03305135` (previous website deployment); keep the database for historical totals.

DMG release: `install_click` positions `hero_download` and `install_download` record direct DMG link clicks, separately from historical `hero`/`nav` install-section clicks. Clicks do not prove completed downloads or installations.

`functions/_middleware.js` redirects every old-domain path and query to the new domain with HTTP 301. `docs/_routes.json` keeps the middleware enabled for static files and API paths. The API accepts same-origin Origin, or same-origin Referer only when Origin is absent; untrusted Origin cannot fall back to Referer.

Tests: `node analytics/tests/client.cjs && node analytics/tests/server.mjs`.
