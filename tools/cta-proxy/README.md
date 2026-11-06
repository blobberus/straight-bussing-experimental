# CTA proxy: live CTA buses for Straight Bussing (owner steps)

Straight Bussing shows the CTA bus routes that serve Hyde Park. Without this proxy it shows CTA's **published
schedule only** ("Scheduled times · CTA live data not connected"; every CTA time is marked as a schedule
estimate, and no CTA bus is drawn). Live CTA buses and arrival predictions come from the **CTA Bus Tracker
API**, which needs a secret developer key and does not allow browsers to read it directly (no CORS). A key
must never be put in the website or the app, where anyone could copy it. So a tiny server, this Cloudflare
Worker, holds the key and answers one read-only address for everyone:

```
website / app  --GET /cta/v1/live.json-->  this Worker (key secret, 25 s cache)  -->  CTA Bus Tracker API v3
```

- `worker.js`: the whole Worker (no build step, no npm). One endpoint, `/cta/v1/live.json`, plus
  `/cta/v1/health` (counts only). Every other address answers 404, only GET is allowed, and no query parameter is
  ever passed on to CTA, so it cannot be used as an open relay to CTA.
- One CTA refresh every 25 seconds at most, shared by all riders: the CTA quota does not grow with riders.
- CORS: only `https://blobberus.github.io` (the live site and the experimental site share this origin), plus any
  origins you list in `EXTRA_ORIGINS` for local testing.
- What it gets from a rider: nothing but the request itself. The app sends no location, no stop, no id (only a
  cache-busting number). The Worker stores and logs nothing about riders.
- Tests: `python tools/test_cta_proxy.py` (headless Edge, made-up CTA answers; no Cloudflare needed).

## Steps (about 30 minutes, plus CTA's approval wait)

### 1. Get a CTA Bus Tracker API key (free)
1. Go to <https://www.ctabustracker.com>, choose **Sign In**, then **Create an account**, and confirm the
   account from the email CTA sends.
2. Signed in, open **My Account**, then **Developer API**, and fill in the request: app name
   "Straight Bussing (unofficial UChicago shuttle tracker)", website
   <https://blobberus.github.io/straight-bussing-experimental/>, and a short description ("shows CTA buses
   serving Hyde Park next to the campus shuttles; one shared server-side cache, about 25,000 calls a day at
   most").
3. Read and accept CTA's Developer License Agreement (<https://www.transitchicago.com/developers/terms/>).
   Save the approval email and a PDF of the terms: App Review may ask for proof of permission.
4. CTA emails the key after approval (one key per account; the default limit is 100,000 calls a day).

### 2. Deploy the Worker on Cloudflare (free plan)
1. Create a free account at <https://dash.cloudflare.com/sign-up> (no credit card needed for Workers).
2. In the dashboard: **Workers & Pages** > **Create** > **Create Worker**. Name it `straight-bussing-cta` and
   click **Deploy** (it deploys a hello-world first).
3. Click **Edit code**, delete everything in the editor, paste the whole of `tools/cta-proxy/worker.js` from this
   repository, and click **Deploy**.
4. Go to the Worker's **Settings** > **Variables and Secrets** > **Add**:
   - Type **Secret**, name `CTA_KEY`, value: your CTA key. **Deploy**.
   - Optional (type Text): `DAILY_LIMIT` (default 90000 CTA calls a day; the Worker stops calling CTA past it and
     reports `budget`), `EXTRA_ORIGINS` (for example `http://127.0.0.1:8000` to test the site locally).
5. Keep logging off: **Settings** > **Observability**: Workers Logs disabled (the Worker writes no logs anyway;
   this keeps Cloudflare from storing request details).
6. Optional but recommended: **Security** > **WAF** > **Rate limiting rules** for your workers.dev or custom
   domain, for example 30 requests per 10 seconds per IP on `/cta/v1/live.json`, so a copied script cannot use up
   the Worker's free daily requests.

### 3. Check it
- Open `https://straight-bussing-cta.<your-subdomain>.workers.dev/cta/v1/health`: `{"ok":true, ...}` (the
  subdomain is shown on the Worker's page).
- Open `https://straight-bussing-cta.<your-subdomain>.workers.dev/cta/v1/live.json`: during CTA service it lists
  `vehicles` and `predictions`; `"ok":false` with `"CTA_KEY is not set"` means step 2.4 is missing; `cta-limit`
  means CTA's daily limit was hit.

### 4. Turn it on in the app
Set the address in `web/js/data/cta-live.js`:

```js
export const CTA_LIVE_URL = 'https://straight-bussing-cta.<your-subdomain>.workers.dev/cta/v1/live.json';
```

then bump the cache name in `web/sw.js` and push (or ask Claude: "turn on live CTA with this proxy URL: ...").
The CTA section of Routes then reads "CTA live data" and CTA buses appear on the map. If the proxy fails, the app
says so ("Scheduled times · CTA live data unavailable") and falls back to the schedule after 2 minutes; the
shuttle data is never affected.

### Turning it off
Set `CTA_LIVE_URL` back to `''` (scheduled times again), or delete the Worker in Cloudflare.

## Budget (from `CTA Implementation.md` in the main repository)
- CTA calls: at most 2 `getvehicles` (14 routes, 10 per call) and about 6 `getpredictions` (buses within 3 km of
  Hyde Park, 10 per call) per refresh, one refresh per 25 s while anyone is using it: about 28,000 a day in the
  worst case (each Cloudflare location keeps its own cache, so up to about twice that), under CTA's 100,000.
- Worker requests: the app asks every 20 s while it is open and visible (paused in a background tab), about 30 per
  10-minute visit; the free plan's 100,000 requests a day covers about 3,000 such visits. The paid plan ($5 a month)
  covers far more.

## Terms (CTA Developer License Agreement)
Straight Bussing stays unofficial: no CTA logo, never "official", the line "Data provided by Chicago Transit
Authority" and "not affiliated with CTA" where CTA data is shown, CTA's own contact (transitchicago.com,
1-888-YOURCTA) on CTA routes and stops. CTA may change the terms or cut access at any time; the app keeps working
with scheduled times if it does.
