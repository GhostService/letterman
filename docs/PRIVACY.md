# Privacy and data protection

Most people using this app are high-school students, many under 18. The public version for users is `server/pb_public/privacy.html` (served at https://hours.tiredghost.com/privacy.html); keep both in sync. This page explains in plain language what the app stores, who can see it, and how it's protected. Keep it accurate if the app changes, and adapt it into a public privacy policy before releasing the app to others.

## What's collected

| Data | Required? | Why |
|---|---|---|
| Email and password | Yes | To sign in, and to verify the account / reset the password |
| Full name | Yes | Shown on hour logs and to organizations you sign up with |
| Phone, school, grade | No | Optional contact details for organizations you sign up with |
| Hour logs: place, address, date, hours, comments | Yes, per log | Your volunteer record |
| Supervisor's name and drawn signature | To count the hours | Proof the hours were done |
| Your own calendar entries | Optional | Your volunteering plans |
| Organization accounts: org name | Yes | Shown on listings |

The app has no ads, no analytics, no tracking, and no location access.

## Who can see what

| | You | Organization you signed up with | Other users | Server admin |
|---|---|---|---|---|
| Your hour logs and signatures | ✅ | ❌ | ❌ | ✅ (dashboard) |
| Your name, email, phone, school, grade | ✅ | ✅ only for their own listings you signed up for | ❌ | ✅ |
| Your calendar entries | ✅ | ❌ | ❌ | ✅ |
| Opportunity listings | ✅ | ✅ | ✅ (all signed-in users) | ✅ |

These rules are enforced **on the server**, not just in the app. A modified app can't get around them. `server/smoke_test.py` checks each one automatically.

Organization (operator) accounts must be **approved by the admin** before they can post or see any student contact details.

## How it's protected

- **In transit:** all traffic uses HTTPS. The database server itself isn't reachable from the internet.
- **Encrypted in the database:** names, phone numbers, schools, grades, everything in hour logs (including signatures), sign-up contact details and calendar entries are encrypted with AES-256-GCM before they're stored. A copied database file or backup is unreadable without the key. (Email addresses, dates and hour counts are not encrypted, because login and sorting need them.)
- **Key kept separate:** the encryption key lives in a root-only file on the server, never in the database or in git.
- **Signed hours can't be changed:** once a supervisor signs, the server locks the entry. The server also records when it was signed, so it can't be backdated.
- **Verified accounts only:** an account can't use the app until its email address is verified.
- **Rate limiting:** repeated login attempts are slowed down.
- **On the phone:** the login token is kept in the iOS Keychain. Logs waiting to upload (no signal) are stored with iOS data protection, which encrypts them while the phone is locked.

What encryption here does *not* protect against: someone who takes over the running server (they could read the key from it). Keep the server updated and the SSH login secure.

## Deleting data

- **Delete my account** (Profile tab) permanently deletes the account and everything in it: hour logs, signatures, sign-ups (the spot is freed) and calendar entries. Export your hours first if you need them.
- Deleting a single log deletes its signature too.
- Signing out removes the account's data from the phone, including the "Volunteering" calendar the app created.
- Backups on the server are kept for 7 days and then overwritten. Encrypted copies the admin downloads are kept until the admin deletes them.

## Ages

The app is meant for high-school students (usually 14–18). It's not meant for children under 13. If it is ever offered to under-13s, US law (COPPA) requires verified parental consent first. Schools may also have their own rules about student data; check with them before rolling it out at a school.
