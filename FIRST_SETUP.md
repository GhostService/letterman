# First setup: from zero to TestFlight

Follow this top to bottom the first time. There are five parts:

| Part | What you get | Time |
|---|---|---|
| [A. Try it on your Mac](#part-a-try-it-on-your-mac-simulator) | The app running in the iPhone Simulator with demo data | 15 min |
| [B. Put the server online](#part-b-put-the-server-online-your-vps) | The real backend at `https://hours.tiredghost.com` | 45–60 min |
| [C. Install on your iPhone](#part-c-install-on-your-iphone-15) | The app on your phone, talking to your server | 10 min |
| [D. First real test](#part-d-first-real-test) | Real accounts, a real listing, a real signed log | 15 min |
| [E. TestFlight for friends](#part-e-testflight-invites-for-your-friends) | The $99 Apple Developer account, and friends installing the app through TestFlight | 1–2 hours of work, plus up to a few days waiting on Apple |

Parts A and B don't depend on each other, so you can do them in either order. Part C needs Part B, and Part E needs Parts B–D.

After that, [docs/MAINTENANCE.md](docs/MAINTENANCE.md) covers day-to-day tasks: approving organizations, backups, updating, and fixing problems.

---

## What you need first

- **A Mac** with **Xcode 26** (free in the Mac App Store; big download, start it early).
- **Homebrew** (a Mac package installer). Check with `brew --version`. If that says "command not found", install it from [brew.sh](https://brew.sh) by pasting this into Terminal and following what it prints:

  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

- **Your VPS** running Ubuntu, its **IP address**, and an SSH login that can use `sudo`. Check it with (on your Mac):

  ```bash
  ssh you@VPS_IP
  ```

  Throughout this guide, replace `you@VPS_IP` with your real login, like `liam@203.0.113.10`.

- **Access to the DNS settings for tiredghost.com** (wherever you bought the domain or manage DNS, like Cloudflare, Namecheap or Porkbun).
- **An iPhone cable** for Part C, and your **Apple ID** (a free one is fine).
- **A password manager** (Apple Passwords works). You'll create four secrets you must not lose; there's a checklist at the end.

Money: nothing beyond the VPS and domain you already have. The email service in step B9 has a free plan that's plenty.

---

## Part A: Try it on your Mac (Simulator)

The Simulator version talks to a test copy of the server running on your Mac, so nothing you do here touches real data.

### A1. Download PocketBase for your Mac

In Terminal, go to the project folder and download it into `server/`:

```bash
cd ~/Desktop/letterman/server
curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.40.4/pocketbase_0.40.4_darwin_arm64.zip
unzip -o pocketbase_0.40.4_darwin_arm64.zip pocketbase && rm pocketbase_0.40.4_darwin_arm64.zip
```

(On an Intel Mac use `darwin_amd64` in both places instead.) This file is in `.gitignore`, so it never goes into git.

### A2. Start the test server

```bash
./dev.sh
```

Leave this Terminal window open; closing it (or pressing Ctrl+C) stops the server. You should see `Server started at http://127.0.0.1:8090`.

If macOS asks whether `pocketbase` may accept incoming network connections, either answer is fine. The test server only listens to your own Mac.

### A3. Add demo data

Open a **second** Terminal window:

```bash
cd ~/Desktop/letterman/server
python3 dev_seed.py
```

That creates these logins (they only exist on your Mac):

| Who | Email | Password |
|---|---|---|
| Demo student | `volunteer@example.test` | `devpassword123` |
| Demo organization | `operator@example.test` | `devpassword123` |
| Test dashboard admin | `admin@example.test` | `devpassword123` |

The test dashboard is at http://127.0.0.1:8090/_/

### A4. Run the app

```bash
open ~/Desktop/letterman/Letterman.xcodeproj
```

In Xcode, choose an iPhone simulator from the device menu at the top middle (e.g. "iPhone 17"), then press **▶** (or ⌘R). The first build takes a minute or two.

### A5. Things to try

- Sign in as the demo student. You'll see 32.5 of 40 hours.
- Tap **+**, type a place name, tap **Get supervisor signature**, type a name, draw a signature, tap **Confirm and sign**, then **Save**.
- **Export**: makes an Excel file with the signatures in it.
- **Opportunities**: sign up for one and watch the spots-left number go down. Then check the **Calendar** tab.
- **Calendar → Sync to iPhone Calendar**: allow access, then open the Simulator's Calendar app.
- **Offline test:** stop the server (Ctrl+C in the first window), log and sign some hours, and the app says "Saved on your phone". Start `./dev.sh` again and pull down on the Hours list; it uploads.
- Sign out and sign in as the demo organization to see listings and who's coming.

**Simulator tips:** if a switch doesn't flip, press it a little longer. If typing lands in the wrong field, click the field first and wait a second.

### A6. Run the security checks (optional, but good to know)

```bash
cd ~/Desktop/letterman/server
python3 smoke_test.py
```

This starts its own throwaway server and checks 44 rules: students can't read each other's logs, organizations only see their own sign-ups, signed logs can't be edited, data is encrypted on disk, no overbooking, and more. Every line should say `PASS`.

### A7. Starting over

Stop `./dev.sh`, delete the test data with `rm -rf ~/Desktop/letterman/server/pb_data`, then repeat A2 and A3.

---

## Part B: Put the server online (your VPS)

What you're building:

```
iPhone app ──HTTPS──▶ Caddy (handles the free HTTPS certificate)
                         │
                         ▼
                   PocketBase (only reachable from inside the server)
                         │
                         ▼
             /opt/letterman/pb_data  (database + nightly backups)
```

Commands starting with `sudo` run **on the VPS** (after `ssh you@VPS_IP`). Steps that say **on your Mac** run in Terminal on your Mac, from the project folder (`cd ~/Desktop/letterman`).

### B1. Point the domain at the VPS

In your DNS settings for tiredghost.com, add:

| Type | Name | Value |
|---|---|---|
| A | `hours` | your VPS IP address |

If your VPS has an IPv6 address, also add an `AAAA` record with name `hours` and that address. If you use Cloudflare, set the record to **DNS only** (grey cloud) so Caddy can get the certificate.

Check it (**on your Mac**; may take a few minutes to start working):

```bash
dig +short hours.tiredghost.com
```

It should print your VPS IP.

### B2. Update the server and turn on the firewall

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y unzip ufw age
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Type `y` if it warns about SSH; you allowed it on the line above.

### B3. Install PocketBase

Find the server's CPU type:

```bash
uname -m
```

`x86_64` → use `linux_amd64` below. `aarch64` → use `linux_arm64`.

```bash
sudo useradd --system --home /opt/letterman --shell /usr/sbin/nologin pocketbase
sudo mkdir -p /opt/letterman/pb_data
cd /tmp
curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.40.4/pocketbase_0.40.4_linux_amd64.zip
unzip -o pocketbase_0.40.4_linux_amd64.zip pocketbase
sudo mv pocketbase /opt/letterman/pocketbase
```

### B4. Copy the app's server files up

**On your Mac:**

```bash
scp -r server/pb_hooks server/pb_migrations server/pb_public server/pocketbase.service server/Caddyfile server/pb.sh you@VPS_IP:/tmp/
```

**On the VPS:**

```bash
sudo cp -r /tmp/pb_hooks /tmp/pb_migrations /tmp/pb_public /tmp/pb.sh /opt/letterman/
sudo chmod +x /opt/letterman/pb.sh
sudo chown -R pocketbase:pocketbase /opt/letterman
```

### B5. Create the encryption key

This random key is what scrambles students' names, phone numbers and signatures inside the database. (More on why, and on what it means for you, in [About the encryption key](#about-the-encryption-key) below.)

```bash
sudo mkdir -p /etc/letterman
echo "PB_FIELD_KEY=$(openssl rand -hex 16)" | sudo tee /etc/letterman/pocketbase.env > /dev/null
sudo chmod 600 /etc/letterman/pocketbase.env
sudo cat /etc/letterman/pocketbase.env
```

**Save the printed value in your password manager right now.** If it's lost, the encrypted data can never be read again, and backups become useless. Don't put it in git or send it to anyone.

### B6. Start PocketBase

```bash
sudo cp /tmp/pocketbase.service /etc/systemd/system/pocketbase.service
sudo systemctl daemon-reload
sudo systemctl enable --now pocketbase
sudo systemctl status pocketbase --no-pager
```

You want `active (running)`. If not, `sudo journalctl -u pocketbase -n 50` shows why (usually a missing or wrong-length key from B5).

It creates all the tables, security rules, rate limits and nightly backups on first start. It also starts again by itself if the server reboots.

### B7. Install Caddy (HTTPS)

These are Caddy's official Ubuntu install steps:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
sudo chmod o+r /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

Use this project's config:

```bash
sudo cp /tmp/Caddyfile /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Check it **on your Mac**:

```bash
curl https://hours.tiredghost.com/api/health
```

You should get `{"message":"API is healthy.",...}`. The app's privacy policy is now live at https://hours.tiredghost.com/privacy.html too (you'll fill in your contact email in Part E). If you get a certificate error, wait a minute and retry; `sudo journalctl -u caddy -n 50` on the VPS shows what's happening (usually DNS from B1 not ready yet).

### B8. Create your admin login

```bash
sudo /opt/letterman/pb.sh superuser upsert you@example.com 'pick-a-long-unique-password'
history -c
```

Use your real email and a strong password, and save it in your password manager. (`history -c` wipes the password from the shell history.)

Now open **https://hours.tiredghost.com/_/** in your browser and sign in. This is your admin dashboard.

### B9. Set up email (required)

New accounts must click a link in an email before they can use the app, so the server has to be able to send email.

1. Sign up for a free email-sending service. **[Brevo](https://www.brevo.com)** or **[Resend](https://resend.com)** are both easy. In it, add your domain `tiredghost.com` and add the DNS records it gives you (same place as B1). Then find its **SMTP** settings: host, port, username, password. Save the password in your password manager.
2. In the dashboard, go to **Settings → Application** and set **Application URL** to `https://hours.tiredghost.com`. Save. (The links inside emails use this; if it's wrong, verification links won't work.)
3. **Settings → Mail settings:** set sender name `Letterman` and sender address `no-reply@tiredghost.com`. Turn on **Use SMTP mail server**, fill in the SMTP details, and save.
4. Click **Send test email** and send one to yourself. Check spam if it doesn't arrive.

### B10. Backups to your Mac (recommended)

The server already backs itself up every night and keeps 7 days, but those copies live on the same server. This keeps an encrypted copy on your Mac too.

**On your Mac**, once:

```bash
brew install age
mkdir -p ~/letterman-backups
age-keygen -o ~/letterman-backups/backup-key.txt
```

It prints a `Public key: age1...` line. Copy that public key. Also save the whole `backup-key.txt` file in your password manager; it's needed to open backups.

**On the VPS** (replace `age1REPLACE_ME` with your public key):

```bash
sudo mkdir -p /opt/letterman/offsite
echo '30 3 * * * root f=$(ls -t /opt/letterman/pb_data/backups/*.zip 2>/dev/null | head -1) && [ -n "$f" ] && age -r age1REPLACE_ME -o /opt/letterman/offsite/latest.zip.age "$f" && chmod 644 /opt/letterman/offsite/latest.zip.age' | sudo tee /etc/cron.d/letterman-backup
```

From the next night on, grab a copy whenever you like (**on your Mac**; weekly is a good habit):

```bash
scp you@VPS_IP:/opt/letterman/offsite/latest.zip.age ~/letterman-backups/backup-$(date +%F).zip.age
```

How to restore one is in [docs/MAINTENANCE.md](docs/MAINTENANCE.md#restoring-a-backup).

---

## Part C: Install on your iPhone 15

The app on a real phone always talks to `https://hours.tiredghost.com`, so finish Part B first.

1. **Xcode → Settings → Accounts → +** → Apple ID → sign in.
2. Open `Letterman.xcodeproj`. In the left sidebar click the blue **Letterman** project, then the **Letterman** target → **Signing & Capabilities** tab → set **Team** to *Your Name (Personal Team)*.
   - If it says the bundle identifier isn't available, change **Bundle Identifier** to something unique like `com.tiredghost.letterman.liam`.
3. Plug in your iPhone, unlock it, and tap **Trust This Computer** if asked.
4. On the iPhone: **Settings → Privacy & Security → Developer Mode** → on. The phone restarts; confirm when asked.
5. In Xcode, pick your iPhone in the device menu at the top and press **▶**.
6. The first time, the phone says the developer isn't trusted. Go to **Settings → General → VPN & Device Management**, tap your Apple ID, then **Trust**. Open the app again.

**Free Apple ID limits:** the app stops opening after **7 days**. Plug in and press ▶ again to renew it. Only your own devices can get it this way. Sharing it with other students needs the paid Apple Developer Program ($99/year) for TestFlight or the App Store.

To make your Team stick if you ever regenerate the project, see [docs/MAINTENANCE.md](docs/MAINTENANCE.md#changing-the-app).

---

## Part D: First real test

Use two different email addresses you can check (a Gmail `+` address works: `you+org@gmail.com` delivers to `you@gmail.com`).

1. **Student account:** in the app, **Create account** with your name and first email. Open the verification email on any device, tap **Verify**, then in the app tap **I've verified my email**.
2. **Organization account:** sign out. Create a second account with the other email, turn on **I'm signing up for an organization**, and add an org name. Verify that email too. The app shows **Waiting for approval**, with a button to email lettermansupport@tiredghost.com.
3. **Approve it:** in the dashboard (**https://hours.tiredghost.com/_/**) → **Collections → users** → open that account → set **role** to `operator` → **Save**. In the app tap **I've been approved**; it switches to **My listings**.
4. **Post a listing:** tap **New**, fill it in, tap **Post**.
5. **Sign up:** sign out, sign in as the student, go to **Opportunities**, and sign up. It appears on the **Calendar** tab.
6. **See who's coming:** sign in as the organization and open the listing. You're on the list, with contact details.
7. **Log and sign hours:** as the student, tap **+**, get a "supervisor" (you) to sign, and save. Try **Export**.
8. **Check the encryption:** in the dashboard, open **Collections → hour_logs**. The values show readable because you're the admin, but in the database file they're stored as `enc:...`. (`python3 smoke_test.py` on your Mac checks this automatically.)

That's everything working for real.

---

## Part E: TestFlight invites for your friends

TestFlight is Apple's beta-testing app. Your friends install it from the App Store, accept your invite, and get your app. Each build works for 90 days, and there's no 7-day limit. You need the paid Apple Developer Program for this.

### E1. Join the Apple Developer Program ($99/year)

**Apple requires the person who enrolls to be 18 or older.** If you're under 18, a parent or guardian enrolls with **their own** Apple ID, and their legal name is shown as the app's developer in TestFlight and the App Store. That's normal for student developers. Do it together, since they'll be agreeing to Apple's contracts.

1. On [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/), sign in with the Apple ID that will own the account (with two-factor authentication turned on).
2. Choose to enroll as an **Individual** (an Organization needs a registered business and a D-U-N-S number, so skip that).
3. Pay the $99. Approval usually takes from a few hours to two days, and you'll get an email.
4. In Xcode → **Settings → Accounts**, add the Apple ID that enrolled. If a parent enrolled, they sign in on your Mac (and approve the two-factor code on their phone). Afterwards you'll see a team like *Their Name (Individual)*.

### E2. Point the project at your team

1. In Xcode → **Settings → Accounts**, click the account and note the **Team ID** (10 letters/numbers, like `ABCDE12345`).
2. In `project.yml`, find the commented line `# DEVELOPMENT_TEAM: ABCDE12345`, remove the `# `, and put your Team ID in.
3. Decide the bundle ID. It's `com.tiredghost.letterman` (`PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`). If you changed it in Part C, put the same value in `project.yml`. **It can never change once the app is in App Store Connect.**
4. If you've picked a real app name, set `CFBundleDisplayName` in `project.yml` now (see [docs/MAINTENANCE.md](docs/MAINTENANCE.md#changing-the-app)).
5. Regenerate the project and commit:

   ```bash
   cd ~/Desktop/letterman
   xcodegen
   git add -A && git commit -m "Set signing team for TestFlight"
   ```

6. Open the project, plug in your iPhone, and press ▶ once. Xcode registers the bundle ID with Apple. (Paid accounts also last a year on your own phone instead of 7 days.)

### E3. Finish the privacy policy page

Apple needs a public privacy policy before outside testers can join.

1. Open `server/pb_public/privacy.html` and replace both `REPLACE-WITH-YOUR-EMAIL` with an email you'll actually read for privacy requests.
2. Read the whole page once. It should match what the app does (it does today, but keep it true if you add features).
3. Upload it (**on your Mac**):

   ```bash
   scp -r server/pb_public you@VPS_IP:/tmp/
   ```

   **On the VPS:**

   ```bash
   sudo cp -r /tmp/pb_public /opt/letterman/
   sudo chown -R pocketbase:pocketbase /opt/letterman
   ```

4. Open https://hours.tiredghost.com/privacy.html and check your email shows.

### E4. Make a demo account for Apple's reviewer

Before outside testers can join, someone at Apple tries the app ("Beta App Review"). They need a login that works right away, without waiting for a verification email.

1. In the app on your phone, create an account like `appreview@tiredghost.com` (any address on your domain or your own `+` address) with a strong password. Give it a name like "App Review", and turn **off** the organization switch.
2. In the dashboard → **Collections → users**, open that account, turn on **verified**, and save.
3. Sign in as it once and log a short example entry with a signature, so the reviewer sees what the app does. Make sure at least one upcoming opportunity exists, posted from your organization test account from Part D.

Keep this account working for as long as you use TestFlight. Apple may re-check later builds.

### E5. Create the app in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**.
2. Fill in:
   - **Platforms:** iOS
   - **Name:** the name people will see. It must be unique across the whole App Store. If "Letterman" is taken, add a few words like `Letterman: Volunteer Hours` (the name on the home screen stays "Letterman"). You can change it later.
   - **Primary language:** English (U.S.)
   - **Bundle ID:** pick `com.tiredghost.letterman` (or yours from E2). If it's not in the list, do step E2.6 first and wait a few minutes.
   - **SKU:** anything only you see, e.g. `letterman-001`
   - **User Access:** Full Access
3. Click **Create**.

### E6. Upload a build

Every upload needs a **higher build number** than the last one. The first upload can use the `1` that's already set. For every later upload, increase `CURRENT_PROJECT_VERSION` in `project.yml` (2, 3, 4…) and run `xcodegen` first.

1. Make sure the server is up: `curl https://hours.tiredghost.com/api/health`. TestFlight builds always use the real server.
2. In Xcode, set the device menu at the top to **Any iOS Device (arm64)**.
3. **Product → Archive.** When it finishes, the **Organizer** window opens.
4. Select the new archive → **Distribute App** → **App Store Connect** → **Distribute**. Leave the default options on (automatic signing, upload symbols).
5. Wait for the email saying the build finished processing (usually 5–30 minutes). It then appears under the app's **TestFlight** tab.

If the upload is rejected with an error code, search Apple's message. The project already includes the privacy manifest and encryption setting that cause most first-upload rejections.

### E7. Try it yourself first (internal testing, no review)

1. App Store Connect → your app → **TestFlight** → **Internal Testing** → **+** to create a group (e.g. "Me"). Add yourself, or the account holder if a parent enrolled. Internal testers must be users on the developer account, so this is just for you, not friends.
2. Add the build to the group. Install **TestFlight** from the App Store on your iPhone, open the invite, and install. Do the Part D tests again on this build.

### E8. Invite your friends (external testing)

1. **TestFlight → Test Information** (left sidebar), fill in:
   - **Beta App Description:** e.g. "Log volunteer hours, get them signed by your supervisor on your phone, and sign up for local volunteer opportunities."
   - **Feedback Email:** your email.
   - **Privacy Policy URL:** `https://hours.tiredghost.com/privacy.html`
   - **Beta App Review Information:** your name, email and phone; check **Sign-in required** and enter the demo account from E4.
   - **Review notes:** something like: "Students log volunteer hours and a supervisor signs on the screen. To test: tap +, enter a place, tap Get supervisor signature, type any name and draw any signature. Opportunities tab: sign up for a listing. Organization accounts are approved manually by the admin, so the demo account is a student account."
2. **External Testing → +** → create a group called "Friends".
3. Add your build to the group and click **Submit for Review**. The first review usually takes about a day. Later builds are often approved faster or automatically.
4. When it's approved, add testers in either of two ways:
   - **By email:** **Testers → +**, then enter each friend's email (the one on their Apple ID). They get an email invite.
   - **Public link:** turn on the group's **Public Link** and send it to friends. Anyone with the link can join, so set a tester limit (e.g. 30) and turn it off when you're done.
5. Your friends install **TestFlight** from the App Store, open your invite or link, tap **Accept**, then **Install**. They create their own account in your app. Organization accounts still need your approval in the dashboard (see [docs/MAINTENANCE.md](docs/MAINTENANCE.md#approving-organization-operator-accounts)).

Each build stops working **90 days** after upload. Before then, upload a new one (E6 with a higher build number), add it to the "Friends" group, and testers get it automatically.

**Before inviting people:** re-read [About the encryption key](#about-the-encryption-key) below, since you'll be holding other students' information. It's a good moment to let a parent or teacher know what you're doing.

### E9. Later: the real App Store

Not needed for TestFlight, but when you're ready to publish, App Store Connect will also ask for:

- screenshots (the Simulator works: ⌘S saves one)
- a description and keywords
- a **support URL** (a simple page in `server/pb_public/` works)
- the **App Privacy** questions. Answer them to match `Letterman/PrivacyInfo.xcprivacy`: name, email, phone, other user content and other data, all linked to the user, used for app functionality, no tracking.
- an age rating

The app already has the in-app account deletion Apple requires.

---

## About the encryption key

**What it is:** `PB_FIELD_KEY` is a random 32-character password that only the server uses. Before the server saves a student's name, phone, school, grade, hour logs or signature, it scrambles them with this key (AES-256 encryption). It unscrambles them only when sending them to someone the rules allow: the student, or an organization they signed up with.

**What it protects against:** someone getting a **copy of the database or a backup**, like a stolen backup file, a misconfigured download, or a leaked VPS snapshot. Without the key, that copy is useless.

**What it doesn't do:** stop the person running the server (you) from reading the data. The key has to be on the server for the app to work, and as admin you can see records in the dashboard. That's normal: every app that stores user data, including school systems, Google and Instagram, can technically read what it stores. Encryption at rest is about outsiders, not the operator.

**Is it legal for you to be able to decrypt it?** Yes. Running a service that stores its users' data, and being able to access it, is normal and legal. What the law cares about is **what you collect, why, who you share it with, how you protect it, and whether people can delete it**. (I'm not a lawyer; this is general information, not legal advice.) The rules that matter here:

- **Only use the data to run the app.** Look at someone's info only when you need to, like approving an organization or fixing a problem for someone who asked. Never sell it, share it, use it for ads, or browse it out of curiosity.
- **Tell people what you collect.** Before real students use it, turn [docs/PRIVACY.md](docs/PRIVACY.md) into a public privacy policy and link it from the app or your website.
- **No kids under 13.** In the US, COPPA requires verified parental consent to collect data from under-13s. High schoolers are older, but if the app is ever offered to younger students, that has to be handled first.
- **If a school gets involved:** student data that a school shares with an app falls under FERPA and, in many US states, student-privacy laws (for example California's SOPIPA). Those mainly say: use it only for the school's purpose, no ads, no selling, keep it secure, delete it when asked. The app already works this way, but a school will likely want a written agreement.
- **Get an adult on board before going big.** Because you'd be holding other students' personal information, talk to a parent and a teacher or school administrator before opening it up beyond friends and testing. Some schools also require a parent's permission for students under 18 to use outside apps.

If you'd rather you *couldn't* see most of it as admin, the dashboard can be set to show only scrambled text for phone numbers, schools, grades and hour logs. You'd still see names, emails and org names, which you need for approvals. Just ask. True "even the admin can't read it" encryption (end-to-end) would break things the app relies on: organizations seeing contact info, and password resets keeping your data. It isn't recommended here.

---

## Your secrets checklist

Save all of these in your password manager. None of them belong in git.

| Secret | Where it came from | If you lose it |
|---|---|---|
| `PB_FIELD_KEY` | Step B5 | Encrypted data and backups can never be read again |
| Dashboard admin email + password | Step B8 | Reset it with `sudo /opt/letterman/pb.sh superuser upsert ...` |
| Email service (SMTP) password | Step B9 | Make a new one in the email service |
| `backup-key.txt` (age) | Step B10 | Your downloaded backups can't be opened |
| VPS SSH login | Your VPS provider | Use your provider's recovery console |
| Apple Developer account (Apple ID) | Step E1 | Apple's account recovery. If a parent enrolled, it's their Apple ID. |
| Beta review demo account password | Step E4 | Reset it in the dashboard, then update it in App Store Connect |

## Where to go next

- **Day-to-day tasks** (approving organizations, backups, updating, shipping new TestFlight builds, troubleshooting): [docs/MAINTENANCE.md](docs/MAINTENANCE.md)
- **How it works:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **What data is stored and who sees it:** [docs/PRIVACY.md](docs/PRIVACY.md)
