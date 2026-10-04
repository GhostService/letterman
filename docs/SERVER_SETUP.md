# Server setup (Ubuntu VPS)

This puts the backend online at **https://hours.tiredghost.com**. It takes about 30–45 minutes the first time.

What you'll end up with:

```
iPhone app ──HTTPS──▶ Caddy (port 443, free automatic certificate)
                         │
                         ▼
                   PocketBase (127.0.0.1:8090, not reachable from the internet)
                         │
                         ▼
             /opt/hourtracker/pb_data  (SQLite database + nightly backups)
```

- **PocketBase** is the whole backend in one program: accounts, login, database, the admin dashboard and email.
- **Caddy** sits in front, handles HTTPS and renews the certificate by itself.

You need: the VPS's IP address, SSH access as a user that can run `sudo`, and access to the DNS settings for `tiredghost.com`.

Lines that start with `sudo` or `ssh` are run **on the VPS** unless the step says "on your Mac".

---

## 1. Point the domain at the VPS

At wherever you manage DNS for tiredghost.com, add a record:

| Type | Name    | Value              |
|------|---------|--------------------|
| A    | `hours` | your VPS IP address |

If your VPS also has an IPv6 address, add an `AAAA` record with the same name too.

Check it worked (can take a few minutes). **On your Mac:**

```bash
dig +short hours.tiredghost.com
```

It should print your VPS IP.

## 2. Update the server and turn on the firewall

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y unzip ufw age
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Only SSH and web traffic get in. PocketBase itself is never exposed.

## 3. Install PocketBase

Check the server's CPU type:

```bash
uname -m
```

`x86_64` means use `linux_amd64` below; `aarch64` means use `linux_arm64`.

```bash
sudo useradd --system --home /opt/hourtracker --shell /usr/sbin/nologin pocketbase
sudo mkdir -p /opt/hourtracker/pb_data
cd /tmp
curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.40.4/pocketbase_0.40.4_linux_amd64.zip
unzip -o pocketbase_0.40.4_linux_amd64.zip pocketbase
sudo mv pocketbase /opt/hourtracker/pocketbase
```

## 4. Copy the app's server files to the VPS

**On your Mac**, from this project folder (replace `you@VPS_IP` with your SSH login):

```bash
scp -r server/pb_hooks server/pb_migrations server/pocketbase.service server/Caddyfile server/pb.sh you@VPS_IP:/tmp/
```

Then **on the VPS**:

```bash
sudo cp -r /tmp/pb_hooks /tmp/pb_migrations /tmp/pb.sh /opt/hourtracker/
sudo chmod +x /opt/hourtracker/pb.sh
sudo chown -R pocketbase:pocketbase /opt/hourtracker
```

## 5. Create the encryption key

Students' personal details are encrypted in the database with this key.

> **Important:** if you lose this key, the encrypted data (names, phone numbers, signatures…) can never be read again. Save a copy somewhere safe **off the server**, like a password manager. Never put it in git or send it to anyone.

```bash
sudo mkdir -p /etc/hourtracker
echo "PB_FIELD_KEY=$(openssl rand -hex 16)" | sudo tee /etc/hourtracker/pocketbase.env > /dev/null
sudo chmod 600 /etc/hourtracker/pocketbase.env
sudo cat /etc/hourtracker/pocketbase.env
```

Copy the printed value into your password manager now. (`openssl rand -hex 16` makes exactly the 32 characters the key needs.)

## 6. Start PocketBase as a service

```bash
sudo cp /tmp/pocketbase.service /etc/systemd/system/pocketbase.service
sudo systemctl daemon-reload
sudo systemctl enable --now pocketbase
sudo systemctl status pocketbase --no-pager
```

You want to see `active (running)`. If not, `sudo journalctl -u pocketbase -n 50` shows why. The most common cause is a missing or wrong-length `PB_FIELD_KEY`.

On first start PocketBase creates all the tables, access rules, nightly backups and rate limits automatically from `pb_migrations`.

> Change records (users, listings…) in the dashboard as much as you like, but don't change **collections** (fields or API rules) there. The server is set to only take those from `pb_migrations` in this repo, so the setup is always reproducible and the security rules stay tested.

## 7. Install Caddy (HTTPS)

These are the official Caddy install steps for Ubuntu:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
sudo chmod o+r /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Use this project's Caddyfile:

```bash
sudo cp /tmp/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

**On your Mac**, check it:

```bash
curl https://hours.tiredghost.com/api/health
```

You should see `{"message":"API is healthy.",...}`. If the certificate isn't ready yet, wait a minute and try again; `sudo journalctl -u caddy -n 50` on the VPS shows progress.

## 8. Create your admin login

```bash
sudo /opt/hourtracker/pb.sh superuser upsert you@example.com 'pick-a-long-unique-password'
```

Use your own email and a strong password (save it in your password manager). Then open **https://hours.tiredghost.com/_/** and sign in. This is the admin dashboard.

> Tip: run `history -c` afterwards so the password doesn't stay in the shell history.

## 9. Dashboard settings (one time)

In the dashboard, open **Settings**:

1. **Application**: set **Application URL** to `https://hours.tiredghost.com`. Verification and password-reset emails use this for their links, so this step matters.
2. **Mail settings**: set the sender name (e.g. `Hour Tracker`) and a sender address on your domain (e.g. `no-reply@tiredghost.com`). Then turn on **Use SMTP mail server** and fill it in from an email-sending service. Any of these work and have a free tier big enough for this app:
   - **Brevo**, **Resend**, or **Mailgun**: sign up, verify `tiredghost.com` by adding the DNS records they give you, then copy their SMTP host, port, username and password here.
   - Or a Gmail account with 2-step verification and an *App password* (host `smtp.gmail.com`, port `587`). Fine for testing; the dedicated services are more reliable for real use.

   Click **Send test email** to make sure it works. Without working email, nobody can verify their account, and unverified accounts can't use the app.

Nothing else needs changing. The migration already set up rate limiting, nightly backups and trusted-proxy headers.

## 10. Approving organization (operator) accounts

When someone signs up with "I'm signing up for an organization" turned on, they start as a volunteer until you approve them:

1. Dashboard → **Collections** → **users**.
2. In the search box, filter with: `operator_requested = true && role != "operator"`
3. Open the person, check the **org_name** and email look legitimate, set **role** to `operator`, and **Save**.

The next time they open the app, they get the organization view. To remove access, set **role** back to empty or `volunteer`.

Only approve people you trust. Operators can see contact details of students who sign up for their listings.

## 11. Backups

PocketBase already makes a backup every night at 3:00 AM (server time) and keeps the last 7, in `/opt/hourtracker/pb_data/backups/`. You can also make or download one any time from **Dashboard → Settings → Backups**.

A backup that only lives on the same server doesn't help if the server dies, so keep an **encrypted copy on your Mac** too.

**On your Mac**, install `age` and make a key pair (once):

```bash
brew install age
mkdir -p ~/hourtracker-backups
age-keygen -o ~/hourtracker-backups/backup-key.txt
```

It prints a public key starting with `age1…`. Keep `backup-key.txt` private and safe; it's needed to open backups.

**On the VPS**, create the nightly encrypt job (replace `age1…` with your public key):

```bash
sudo mkdir -p /opt/hourtracker/offsite
echo '30 3 * * * root f=$(ls -t /opt/hourtracker/pb_data/backups/*.zip 2>/dev/null | head -1) && [ -n "$f" ] && age -r age1REPLACE_ME -o /opt/hourtracker/offsite/latest.zip.age "$f" && chmod 644 /opt/hourtracker/offsite/latest.zip.age' | sudo tee /etc/cron.d/hourtracker-backup
```

**On your Mac**, pull the latest encrypted backup whenever you like (or weekly):

```bash
scp you@VPS_IP:/opt/hourtracker/offsite/latest.zip.age ~/hourtracker-backups/backup-$(date +%F).zip.age
```

To restore: decrypt with `age -d -i ~/hourtracker-backups/backup-key.txt -o backup.zip backup-....zip.age`, then upload `backup.zip` in **Dashboard → Settings → Backups** and click restore. The server must be using the **same `PB_FIELD_KEY`** the backup was made with.

## 12. Updating the server later

When the files in `server/pb_hooks` or `server/pb_migrations` change, **on your Mac**:

```bash
scp -r server/pb_hooks server/pb_migrations you@VPS_IP:/tmp/
```

**On the VPS:**

```bash
sudo cp -r /tmp/pb_hooks /tmp/pb_migrations /opt/hourtracker/
sudo chown -R pocketbase:pocketbase /opt/hourtracker
sudo systemctl restart pocketbase
```

New migrations run automatically on restart. To update PocketBase itself, repeat step 3's download with the new version number, then `sudo systemctl restart pocketbase`. Read its release notes first.

## Troubleshooting

| Problem | Check |
|---|---|
| App says it can't connect | `curl https://hours.tiredghost.com/api/health` from your Mac. Then `sudo systemctl status pocketbase caddy` on the VPS. |
| `PB_FIELD_KEY must be set to exactly 32 characters` in the logs | `/etc/hourtracker/pocketbase.env` is missing or the key isn't 32 characters. |
| Verification emails never arrive | Settings → Mail settings → Send test email. Check the Application URL. Check spam. |
| Someone is stuck on "Check your email" | In the dashboard, open their user record and turn on **verified**, if you're sure the email is theirs. |
| Logs | `sudo journalctl -u pocketbase -f` and Dashboard → Logs |
