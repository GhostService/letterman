# Architecture

## Overview

```
┌──────────────────────────┐        HTTPS        ┌────────────┐      ┌───────────────────────────┐
│ iOS app (SwiftUI)        │ ─────────────────▶ │   Caddy    │ ───▶ │ PocketBase                │
│  Keychain: login token   │                     │ TLS, HSTS  │      │  pb_migrations: schema +  │
│  Outbox: offline logs    │                     └────────────┘      │    API rules (security)   │
│  EventKit: "Volunteering"│                                          │  pb_hooks: encryption,    │
│  calendar                │                                          │    sign-up limits, sig.   │
└──────────────────────────┘                                          │  SQLite in pb_data/       │
                                                                      └───────────────────────────┘
```

**Why these choices**

- **SwiftUI, no SDKs.** Native iOS gives PencilKit (signatures), EventKit (Calendar sync) and a native month calendar for free. The only third-party package is [libxlsxwriter](https://github.com/jmcnamara/libxlsxwriter), used for the Excel export, because a spreadsheet with embedded pictures isn't something to hand-write.
- **PocketBase** is one ~40 MB program with auth, database, admin UI, email and backups. That's the least to run and maintain on a single VPS. Its REST API is small enough that the app talks to it with ~150 lines of `URLSession` (`Letterman/Core/PocketBase.swift`).
- **The server enforces every rule.** The app is treated as untrusted; API rules in the migration and checks in hooks decide who can do what. `server/smoke_test.py` proves each rule.

## Data model

All in `server/pb_migrations/1759600000_init.js`. 🔒 = encrypted at rest.

**users** (PocketBase auth collection): email, password, verified, name🔒, phone🔒, school🔒, grade🔒, role (`operator` or empty), operator_requested, org_name, hours_goal
- Users can only read and change their own record. They can never set `role` or `verified` themselves; only the admin can.

**hour_logs**: owner, started_at, hours, place_name🔒, address🔒, comments🔒, signature🔒 (base64 PNG), signer_name🔒, signed_at, opportunity
- `opportunity` links a log to the listing it was logged from ("Log your hours" after a signed-up shift). Deleting the listing clears it and keeps the log.
- Only the owner can see them.
- **Locked once signed:** the update rule requires `signature = ""`, so a signed log can't be changed by anyone but the admin.
- A hook requires a supervisor name with every signature, checks it's a PNG, and sets `signed_at` itself (no backdating).

**opportunities**: operator, title, org_name, description, address, starts_at, duration_hours, spots_needed, lat, lng
- `lat`/`lng` come from the Apple Maps suggestion the operator picks for the address. Not encrypted (the address is public to verified users).
- Every verified user can browse. Only approved operators can create them, and only for themselves.
- `spots_filled` isn't stored; a hook counts sign-ups on every read, so it can never drift.
- `spots_needed` can't be lowered below the number already signed up.
- When an operator changes an upcoming listing's time, length or address, or deletes it, a hook emails everyone signed up (one message, attendees in BCC). The email says to open the app rather than stating the new time, because the server doesn't know each student's time zone. A mail failure is logged and never blocks the operator.

**signups**: opportunity, volunteer, plus a contact snapshot: name🔒, email🔒, phone🔒, school🔒, grade🔒
- Visible to that volunteer and to the operator who owns the listing. Nobody else.
- The snapshot is copied from the volunteer's profile by a hook. That's how operators get contact info without ever being allowed to read the `users` collection.
- **No overbooking:** the hook counts sign-ups and inserts inside one database transaction. The smoke test fires 8 simultaneous sign-ups at 3 spots and checks exactly 3 succeed.
- A unique index stops signing up twice. Operators can't sign up. Past opportunities can't be signed up for.

**calendar_events**: owner, title🔒, starts_at, duration_hours, location🔒, notes🔒. Owner-only.

Deleting a user cascades to their logs, sign-ups (freeing spots) and calendar entries. Deleting a listing removes its sign-ups.

## Encryption at rest

`server/pb_hooks/lib.js` lists the encrypted fields per collection.

- **Write:** `onRecordCreateExecute` / `onRecordUpdateExecute` run right before the SQL insert/update and replace each listed value with `enc:` + AES-256-GCM ciphertext. Values already starting with `enc:` are left alone, so unchanged fields aren't double-encrypted.
- **Read:** `onRecordEnrich` decrypts just before a record is sent to someone who already passed the API rules.
- **Key:** `PB_FIELD_KEY` (32 characters) from a root-only env file. The server refuses to start without it. The same key encrypts PocketBase's own settings (`--encryptionEnv`), such as the SMTP password.
- Signatures are stored as base64 text rather than PocketBase files, so they get the same encryption.

## The iOS app

```
Letterman/
  LettermanApp.swift   app entry, routes to sign-in / verify email / volunteer tabs / operator tabs
  Core/
    Config.swift          server URL (local server in the Simulator, real server everywhere else)
    PocketBase.swift      REST client, error messages, date format
    Session.swift         sign in/up/out, token in Keychain, profile, delete account
    Models.swift          Codable mirrors of the collections
    VolunteerStore.swift  logs, opportunities, sign-ups, calendar; offline outbox upload
    OperatorStore.swift   an operator's listings and attendees
    Outbox.swift          logs waiting for a connection (file protected by iOS)
    CalendarSync.swift    "Volunteering" calendar in the iPhone Calendar app
    Reminders.swift       local notifications before shifts and a "log your hours" nudge after
    Geo.swift             Apple Maps address suggestions and lookups, one-off GPS reading, distances
    Export.swift          PDF report of signed hours, and .xlsx export of every log, both with signature images
    Keychain.swift
  PrivacyInfo.xcprivacy   Apple privacy manifest (required for TestFlight / App Store uploads)
  UI/                     one file per screen group; Theme.swift has colors, fonts and shared pieces
  Fonts/                  Big Shoulders Display + Figtree (SIL Open Font License)
```

**Offline logging.** Volunteer sites often have poor signal. If saving a log fails because there's no connection, the log (including the signature PNG) goes into an outbox file on the phone and is shown as "Saved on your phone". It uploads automatically when the network comes back, when the app reopens, or on pull-to-refresh. Each new log gets its id on the phone, so a retry after a lost reply can't create a duplicate. If the server *rejects* a pending log, it stays with the reason shown until the student discards it. Nothing is silently dropped.

**Near me.** Organizations must pick their listing's address from Apple Maps suggestions, which gives every listing exact coordinates. Students set an area (a typed ZIP/town, or one GPS reading) and a radius of 5, 10, 25 or 50 miles. The app already downloads every upcoming listing, so it filters by distance on the phone; the student's area is stored only in the app's local settings and never sent to the server. Listings saved before coordinates existed are always shown.

**Reminders and logging shifts.** With "Remind me before shifts" on, the app schedules local notifications (no push server) for the next 20 calendar items: 7 PM the evening before and an hour before, plus, for sign-ups, a nudge when the shift ends. When a signed-up shift has ended and has no log yet, the Hours tab offers a log prefilled from the listing, ready for the supervisor to sign.

**Calendar sync.** When turned on, the app owns one calendar named "Volunteering" and, on every change, replaces its upcoming events with the current sign-ups and custom entries. It never touches the user's other calendars. Turning sync off or signing out deletes that calendar.

**Design.** "Letterman" (see `docs/designs/b-letterman.html`): forest green and varsity gold, condensed Big Shoulders numbers, gold stripe under each header, stitched "patch" for signed hours. Supports Dynamic Type and dark mode.

## Testing

- `server/smoke_test.py`: 40+ checks against a throwaway PocketBase (permissions, encryption on disk, overbooking race, lock-after-signing, cascade delete, no duplicate uploads).
- The app was exercised end to end in the iOS Simulator against `server/dev.sh` + `server/dev_seed.py`. Screenshots are in `docs/screenshots/`.

## Not built (yet)

| Idea | Why not now |
|---|---|
| Push notifications when someone signs up | Need the paid Apple Developer account. Operators see the current sign-ups whenever they open or refresh a listing. |
| Android / web app | iPhone only for now. |
| Browsing listings offline | Only hour logging needs to work without signal. |
| Teams of operators per organization | Each operator account manages its own listings. |
