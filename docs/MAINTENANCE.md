# Maintenance

Day-to-day tasks once everything from [FIRST_SETUP.md](../FIRST_SETUP.md) is done. `you@VPS_IP` means your SSH login. "On your Mac" commands run from the project folder.

## Approving organization (operator) accounts

People who sign up with "I'm signing up for an organization" see a **Waiting for approval** screen until you approve them. It has a button that emails lettermansupport@tiredghost.com with their organization name and account email.

1. Open **https://hours.tiredghost.com/_/** → **Collections → users**.
2. In the search box, filter: `operator_requested = true && role != "operator"`
3. Open the person. Check the **org_name** and email look real (an organization email or website helps), set **role** to `operator`, and **Save**.

Their app switches to the organization view the next time they open it. To take access away, clear **role** and save; they go back to the waiting screen. To turn someone down, or to make them a regular volunteer instead, also untick **operator_requested** (or delete the account).

Only approve people you trust: operators see the contact details of students who sign up for their listings.

**Rule of thumb for the dashboard:** editing *records* (users, listings, logs) is fine. Don't change *collections* (fields or API rules) there. The server only loads those from `server/pb_migrations`, so the security rules stay the ones `smoke_test.py` checks.

## Helping someone

| Situation | What to do |
|---|---|
| Stuck on "Check your email" | Have them check spam and tap **Send the email again**. If you're sure the email is theirs, open their user record and turn on **verified**. |
| Forgot password | **Sign in → Forgot password?** sends a reset email. |
| Wants their data deleted | They can tap **Profile → Delete my account**. Or delete their user record in the dashboard; everything of theirs is deleted with it. |
| A log has a mistake but is already signed | Signed logs are locked on purpose. The student can delete it and log it again with a new signature. |

## Shipping a new TestFlight build

Do this when you've changed the app, and at least every 90 days (TestFlight builds expire after 90 days).

1. Test it in the Simulator against the local server (FIRST_SETUP.md, Part A).
2. In `project.yml`, increase `CURRENT_PROJECT_VERSION` by one. For a bigger release, also raise `MARKETING_VERSION` (e.g. `1.0` → `1.1`). Then run `xcodegen` and commit.
3. If the server changed too, update it first (see [Updating the server](#updating-the-server)), so the new app never talks to old server rules.
4. Xcode: device menu **Any iOS Device (arm64)** → **Product → Archive** → **Distribute App** → **App Store Connect**.
5. When processing finishes, App Store Connect → **TestFlight** → add the build to the "Friends" group. Fill in **What to Test** so testers know what changed.

## Renewing the app installed straight from Xcode

Apps installed with ▶ from Xcode (not TestFlight) stop opening after **7 days** with a free Apple ID, or about **a year** with the paid program. Plug in the phone, open `Letterman.xcodeproj`, pick your iPhone, and press ▶. Your data is on the server, so nothing is lost.

## Backups

The server makes a backup zip every night at 3:00 AM (server time) and keeps 7, in `/opt/letterman/pb_data/backups/`. You can also make or download one any time from **Dashboard → Settings → Backups**.

If you set up step B10, grab the encrypted copy now and then (**on your Mac**):

```bash
scp you@VPS_IP:/opt/letterman/offsite/latest.zip.age ~/letterman-backups/backup-$(date +%F).zip.age
```

### Restoring a backup

1. **On your Mac**, decrypt it:

   ```bash
   age -d -i ~/letterman-backups/backup-key.txt -o ~/letterman-backups/restore.zip ~/letterman-backups/backup-YYYY-MM-DD.zip.age
   ```

2. **Dashboard → Settings → Backups → Upload backup**, choose `restore.zip`, then click **Restore** on it. The server restarts with that data.
3. The server must have the **same `PB_FIELD_KEY`** that was in use when the backup was made. If you're restoring onto a brand-new server, do steps B2–B7 of FIRST_SETUP.md first, using your saved key in B5 instead of making a new one:

   ```bash
   echo "PB_FIELD_KEY=paste-your-saved-key" | sudo tee /etc/letterman/pocketbase.env > /dev/null
   ```

Delete `restore.zip` afterwards; it isn't encrypted.

## Updating the server

When files in `server/pb_hooks`, `server/pb_migrations` or `server/pb_public` change, **on your Mac**:

```bash
cd server && python3 smoke_test.py && cd ..
scp -r server/pb_hooks server/pb_migrations server/pb_public you@VPS_IP:/tmp/
```

**On the VPS:**

```bash
sudo cp -r /tmp/pb_hooks /tmp/pb_migrations /tmp/pb_public /opt/letterman/
sudo chown -R pocketbase:pocketbase /opt/letterman
sudo systemctl restart pocketbase
```

New migrations run automatically when it restarts.

**Updating PocketBase itself:** read its [release notes](https://github.com/pocketbase/pocketbase/releases) first. Then download the new version as in step B3, test it locally (put the Mac version in `server/` and run `python3 smoke_test.py`), replace `/opt/letterman/pocketbase` on the VPS, and run `sudo systemctl restart pocketbase`.

**Updating Ubuntu:** `sudo apt update && sudo apt upgrade -y` every few weeks. Caddy updates through this too.

## Changing the app

- **The Xcode project is generated** from `project.yml` by XcodeGen. After **adding or renaming Swift files** or editing `project.yml`, run:

  ```bash
  brew install xcodegen   # once
  xcodegen
  ```

  This resets the signing Team. To keep it, add your team ID (Xcode → Settings → Accounts) to `project.yml` under `targets → Letterman → settings → base`:

  ```yaml
  DEVELOPMENT_TEAM: ABCDE12345
  ```

- **App name:** `CFBundleDisplayName` in `project.yml` (then `xcodegen`), plus the title in `Letterman/UI/AuthView.swift`.
- **Server address:** `Letterman/Core/Config.swift`. If you change domains, also update `server/Caddyfile` and the Application URL in the dashboard.
- **Colors and fonts:** `Letterman/UI/Theme.swift`.
- **Test locally first:** `cd server && ./dev.sh`, then run in the Simulator (FIRST_SETUP.md, Part A).

## If you set things up before the rename to Letterman

The app used to be called "Hour Tracker". If you already followed an older version of FIRST_SETUP.md, your server uses `/opt/hourtracker` and `/etc/hourtracker`. Move them to the new names once.

**On your Mac**, from the project folder:

```bash
scp -r server/pb_migrations server/pb_public server/pocketbase.service server/pb.sh you@VPS_IP:/tmp/
```

**On the VPS:**

```bash
sudo systemctl stop pocketbase
sudo mv /opt/hourtracker /opt/letterman
sudo mv /etc/hourtracker /etc/letterman
sudo usermod -d /opt/letterman pocketbase
sudo cp -r /tmp/pb_migrations /tmp/pb_public /tmp/pb.sh /opt/letterman/
sudo chmod +x /opt/letterman/pb.sh
sudo chown -R pocketbase:pocketbase /opt/letterman
sudo cp /tmp/pocketbase.service /etc/systemd/system/pocketbase.service
sudo systemctl daemon-reload
sudo systemctl start pocketbase
sudo systemctl status pocketbase --no-pager
```

On startup a migration renames the app in emails from "Hour Tracker" to "Letterman". Also change the sender name in **Dashboard → Settings → Mail settings** to `Letterman`.

If you set up the backup job (step B10), update it too:

```bash
sudo sed -i 's|/opt/hourtracker|/opt/letterman|g' /etc/cron.d/hourtracker-backup
sudo mv /etc/cron.d/hourtracker-backup /etc/cron.d/letterman-backup
```

And on your Mac: `mv ~/hourtracker-backups ~/letterman-backups`.

The bundle ID also changed to `com.tiredghost.letterman`, so a phone that had the old app gets Letterman as a separate app. Delete the old "Hour Tracker" app and sign in again in Letterman. No data is lost, since it's all on the server.

## Troubleshooting

| Problem | Check |
|---|---|
| App says it can't connect | On your Mac: `curl https://hours.tiredghost.com/api/health`. On the VPS: `sudo systemctl status pocketbase caddy`. |
| `PB_FIELD_KEY must be set to exactly 32 characters` in the logs | `/etc/letterman/pocketbase.env` is missing, or the key isn't 32 characters. |
| HTTPS / certificate errors | `dig +short hours.tiredghost.com` must show the VPS IP; `sudo journalctl -u caddy -n 50`. Ports 80 and 443 must be open (`sudo ufw status`). |
| No verification emails | Dashboard → Settings → Mail settings → **Send test email**. Check the Application URL and spam. |
| App won't open on the iPhone | Installed from Xcode: press ▶ again (7-day / 1-year limit). From TestFlight: the build expired after 90 days, so upload a new one. |
| TestFlight upload rejected | Read the error code in the email. Most common: the build number wasn't increased (`CURRENT_PROJECT_VERSION`). |
| Something else | `sudo journalctl -u pocketbase -f` on the VPS, and **Dashboard → Logs**. |
