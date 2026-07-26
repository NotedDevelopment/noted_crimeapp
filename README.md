# noted_crimeapp — "Citizen" for LB Phone

A Citizen-style community-safety app for LB Phone. Players see incidents around
them in real time on a live Los Santos map, report incidents with photos and
videos, confirm and comment on each other's reports, and build a reporter
reputation. Police/EMS/press get verified badges, police can moderate, a crime
heatmap tracks dangerous areas over time, and the SOS button fires straight to
dispatch.

## Feature list

### Accounts & identity

- **Username + password accounts** — created and logged into from the app's
  landing screen (Create account / Log in). Passwords are salted SHA-256;
  create requires password confirmation.
- **Sessions** — each character stays logged in across relogs until Sign out;
  an account can be logged into from any character.
- **Reset password** — from the profile (current + new + confirm).
- **Reputation ladder** — cosmetic levels (Reporter → Trusted Citizen → Local
  Watch → Guardian, fully configurable). Points for posting and per unique
  confirmation received; belongs to the account, derived from points, never
  stored.
- **Verified job badges** — config map (`police → LSPD`, `ambulance → EMS`,
  `reporter → Press`) shown on reports, comments, and profiles.

### The map

- **Live Los Santos map** — Leaflet over a bundled 4K atlas; no external tiles.
- Opens **centered on you**; a blue dot tracks your position; recenter button.
- **Hard bounds** — you can never zoom or pan far enough to see off-map void,
  and zoom-out keeps enough headroom to pan the whole map.
- **Live markers** — every active report, icon/color by category & severity;
  tap to open the incident. New reports appear instantly on every open map.
  Markers are 32 px with the category glyph inside; `ui/src/map.ts` also has a
  luminance-based dark-glyph mode (currently commented out) to flip the icon
  dark on bright severity colors if white washes out.
- **Draggable alerts sheet** — grabber with three snap heights (peek / normal
  / expanded); peek tucks the list away so the whole map is free to pan.
- **Nearby range picker** — tap "`N within 1 mi · nearby`" to pick the radius
  (500 ft → 5 mi imperial, 250 m → 5 km metric); choice persists.

### Reporting

- **Category grid** from config (fight, shots fired, theft, fire, …) plus an
  optional free-text **Custom** report tile.
- **Photos & videos** — capture with the phone camera or pick from the
  gallery, up to a config cap; videos get real thumbnails and a fullscreen
  player.
- **Server-authoritative** — report position always comes from the server's
  read of the poster; category/severity re-resolved server-side; length caps
  and per-player cooldowns enforced server-side.
- **SOS button** — cooldown-gated, fires a config function (ships wired to
  ps-dispatch `CustomAlert`; swap in any dispatch in one function). Disabling
  `Config.SOS.enabled` removes the button from the app entirely.

### Community

- **Confirmations** — "I see it too", once per player, credits the author.
- **Comments** — threaded under each incident, badge-aware, length-capped.
- **Directions** — sets a GPS waypoint to the incident.
- **Proximity notifications** — opt-in (persisted per account), only online
  subscribers within the radius are pinged; master kill-switch in config.
- **Moderation** — authors delete their own reports; police at/above a config
  grade or an ace permission delete anything (re-checked server-side).
- **Admin mode** — moderators get a shield toggle in the map header; turning
  it on swaps each alert row's chevron for a delete button and adds a delete
  button next to every comment. Every delete is re-validated server-side, so
  the toggle is purely a display convenience.
- **Discord webhook logging** — optional (`Config.Logging`): report posted
  (embed colored by severity), report deleted (flags author vs moderator),
  comment posted, comment deleted, SOS fired, account created. Each event can
  be toggled individually; fire-and-forget, so a dead webhook never affects
  gameplay.

### Crime heatmap (optional, SQL-backed)

- Every report **warms its map block** (per-severity counts in `crimeapp_heat`);
  heat **cools over time** via a decay pass and **survives restarts**.
- **Flame button** toggles a smooth blurred heatwave overlay (blue → yellow →
  red) with **severity filter chips** — filtering by e.g. High shows only
  blocks with high-severity reports.
- **Most Dangerous / Safest rankings** — areas ranked by report count under
  the active filter; **tap a row to fly the map there**.
- **Named areas** — config circles rename blocks under your label and always
  appear in rankings (even at 0 reports, so "Safest" is meaningful).
- Heatmap UI only exists when `Config.Heatmap.enabled` or `Config.Showcase`
  is on.

### Search

- Text search over titles, streets, areas; **category & neighbourhood chips**
  (collapsed to 4 with a `+N ›` expander); with-photos/videos filter — all
  instant, client-side.

### Showcase mode

- `Config.Showcase = true` seeds ~48 demo reports across the whole map
  (staggered ages, badges, confirms, comments) plus district heat data — all
  in-memory, SQL untouched — so every feature can be demoed without players.

## Dependencies

`lb-phone`, `qbx_core`, `ox_lib`, `oxmysql`. Load **after** lb-phone.

## Install

1. Place the resource at `resources/[ktest]/noted_crimeapp` (or anywhere your
   cfg ensures **after** lb-phone and the dependencies above).
2. Build the UI once (ships pre-built; rebuild only after UI edits):
   ```bash
   cd ui && npm install && npm run build
   ```
3. Ensure it (`ensure noted_crimeapp`, or via a category like `ensure [ktest]`).
4. Done — all tables auto-create on first start (no SQL import), and the app
   auto-registers with lb-phone (installed by default, named **Citizen**).

> **Upgrading from a pre-password version:** the old citizenid-keyed accounts
> table migrates automatically on boot. Users keep their points and stay
> logged in; since old accounts have no password yet, **their first login (or
> Reset password) claims one** — whatever password they enter first becomes
> theirs.

## Configuration (`config.lua`)

| Key                     | What it controls                                                                                                     |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `Config.AppInfo`        | App identifier, display name, description, default-install                                                           |
| `Config.Categories`     | The report grid: id, label, Font Awesome icon, severity                                                              |
| `Config.CustomReports`  | Allow free-text reports + their severity                                                                             |
| `Config.Severities`     | Severity labels + colors (tags, markers, heat)                                                                       |
| `Config.Points`         | Points for posting / per confirmation received                                                                       |
| `Config.Levels`         | Reputation ladder (name + threshold), fully editable                                                                 |
| `Config.Badges`         | Job name → verified badge label                                                                                      |
| `Config.Moderation`     | Job → min grade that can delete any report; ace fallback                                                             |
| `Config.Notifications`  | Master switch, radius (metres), default opt-in                                                                       |
| `Config.ReportLifetime` | Minutes a report stays live (swept every ~60 s)                                                                      |
| `Config.Cooldowns`      | Report / comment / SOS / login cooldowns (seconds)                                                                   |
| `Config.Media`          | Max attachments per report, allow video                                                                              |
| `Config.Limits`         | Server-enforced length caps (username, password, texts)                                                              |
| `Config.SOS`            | Enable/hide the SOS button + the dispatch function (default: ps-dispatch)                                            |
| `Config.Units`          | `'imperial'` (ft/mi, default) or `'metric'` (m/km)                                                                   |
| `Config.Logging`        | Discord webhook logging: bot name, per-event toggles (URL goes in `server/logs.lua` — config is shared with clients) |
| `Config.Heatmap`        | SQL heat tracking: cell size, cap, decay, named areas                                                                |
| `Config.Showcase`       | Demo mode: seeded reports + heat, heatmap without SQL                                                                |

### Discord logging setup

1. Paste your webhook URL into `WEBHOOK_URL` at the top of `server/logs.lua`.
   It lives there — not in `config.lua` — on purpose: config is a
   `shared_script`, so anything in it is readable by every client.
2. Set `Config.Logging.enabled = true`. Silence individual events via
   `Config.Logging.events` (report, deleteReport, comment, deleteComment,
   sos, account).
3. After first adding `server/logs.lua` to the manifest, run `refresh` before
   `restart noted_crimeapp` — a plain restart reuses the cached manifest. If
   the file isn't loaded, the resource prints a red console warning and stubs
   logging out so gameplay callbacks never error.

## Data & persistence

- **Persistent (oxmysql, all auto-created):**
  - `crimeapp_accounts` — username (key), salted password hash, avatar,
    points, notification opt-in.
  - `crimeapp_sessions` — which account each character is logged into.
  - `crimeapp_heat` — per-cell, per-severity heat counts (only when
    `Config.Heatmap.enabled`).
- **Ephemeral (by design):** reports, confirmations, comments live in server
  memory and wipe on restart. Nothing to clean up.

## Security model

- Report coordinates come from the server's read of the poster's ped — the
  client never supplies a position.
- Every mutating callback re-validates session, permissions, cooldowns, and
  length caps server-side; the UI's delete button is a display hint only.
- Passwords are salted SHA-256 hashed in the database; plaintext is never
  stored. (Game-grade auth — fine for RP, not for reused real passwords.)
- Author `citizenid` is never sent to clients.
- The Discord webhook URL lives in server-only `server/logs.lua`, never in the
  shared config; webhook sends are fire-and-forget and cannot block or crash
  gameplay callbacks.

## Development

```bash
cd ui
npm start          # Vite dev server on :3000 (switch ui_page in fxmanifest)
npm test           # Vitest unit tests (helpers: distance, heat, filters)
npm run typecheck  # tsc --noEmit (build alone does NOT type-check)
npm run build      # production build → ui/dist (ui_page default)
```

Dev `ui_page` line is in `fxmanifest.lua` (commented); keep `ui/dist/index.html`
active for production.

## In-city QA checklist

1. Fresh start → tables auto-created; create account (password + confirm);
   duplicate username rejected inline; sign out → log back in.
2. Reset password from profile; sign out; old password fails, new one works.
3. Post a report with photo + video → second client within radius gets a
   phone notification; their open map gains the marker live; video plays
   fullscreen.
4. Confirm + comment from the second client → author points rise; level bar
   moves.
5. Delete: author ✓; police ≥ min grade ✓; low-grade cop ✗; civilian ✗; ace ✓.
   Admin mode: shield button only appears for moderators; toggling it on shows
   delete buttons on alert rows and comments, and both work; civilians never
   see the shield.
6. SOS → alert lands in ps-dispatch with correct coords/street; cooldown
   message on immediate retry; `Config.SOS.enabled = false` removes the
   button from the report sheet.
7. Heatmap (enable `Config.Heatmap.enabled` or Showcase): flame button shows
   the overlay; severity chips filter; rankings fly the map to areas.
8. Restart → reports wiped; accounts/points/opt-in/sessions/heat persist.
9. `Config.Notifications.enabled = false` → no pings; everything else works.
10. Logging: webhook URL in `server/logs.lua` + `Config.Logging.enabled = true`
    → post / delete (author vs moderator flagged) / comment / comment-delete /
    SOS / account-create all land as Discord embeds, report embeds colored by
    severity; turning an event off in `Config.Logging.events` silences only
    that event.
11. Report screen: Back button and header clear the phone status area; a short
    incident (no comments/details) fills the screen with no black gap under
    the sheet.

## Deferred by design

- **Go Live** — lb-phone does not expose its WebRTC livestream API to custom
  apps. The report pipeline can carry a `live` flag later without redesign.
- **Automated detection** (auto-posts for gunshots/etc.) — the store treats the
  author as data, so a future system poster needs no schema change.
