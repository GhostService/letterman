# iOS app setup

You need a Mac with **Xcode 26** (free from the Mac App Store) and Homebrew.

## Run it in the Simulator (with a local test server)

The Simulator build talks to a PocketBase server running on your Mac, so you can test without touching the real server.

1. **Get PocketBase for your Mac** (once). From the project folder:

   ```bash
   cd server
   curl -LO https://github.com/pocketbase/pocketbase/releases/download/v0.40.4/pocketbase_0.40.4_darwin_arm64.zip
   unzip -o pocketbase_0.40.4_darwin_arm64.zip pocketbase && rm pocketbase_0.40.4_darwin_arm64.zip
   ```

   (Use `darwin_amd64` instead if your Mac has an Intel chip.)

2. **Start the local server** and leave that terminal open:

   ```bash
   ./dev.sh
   ```

   The local dashboard is at http://127.0.0.1:8090/_/ (login `admin@example.test` / `devpassword123`, only on your Mac).

3. **Add demo data** (optional, in a second terminal):

   ```bash
   cd server && python3 dev_seed.py
   ```

   This makes a demo student (`volunteer@example.test`) and organization (`operator@example.test`), both with password `devpassword123`. To start over, stop the server, delete `server/pb_data`, and run both commands again.

4. **Open the app**: double-click `HourTracker.xcodeproj`, pick an iPhone simulator at the top, and press ▶ (Run).

The local server doesn't send real emails. To verify a new test account, open it in the local dashboard (users collection) and turn on **verified**. To make it an organization, set **role** to `operator`.

## Install on your iPhone 15 (free, no paid developer account)

The app on a real phone always uses the real server (`https://hours.tiredghost.com`), so do [SERVER_SETUP.md](SERVER_SETUP.md) first.

1. Xcode → **Settings → Accounts** → **+** → sign in with your Apple ID.
2. In Xcode, click the **HourTracker** project in the left sidebar → **HourTracker** target → **Signing & Capabilities** → set **Team** to *Your Name (Personal Team)*.
3. Plug in your iPhone and unlock it. When asked, tap **Trust This Computer**.
4. On the iPhone: **Settings → Privacy & Security → Developer Mode** → turn on (the phone restarts).
5. In Xcode, pick your iPhone at the top and press ▶.
6. The first time, the iPhone says the developer isn't trusted. Go to **Settings → General → VPN & Device Management**, tap your Apple ID, and tap **Trust**. Then open the app.

**Free accounts have limits:** the app stops opening after **7 days**. Plug in and press ▶ again to refresh it. Only you can install it this way. To give it to other students you'll need the paid Apple Developer Program ($99/year) for TestFlight or the App Store.

## Things to know when changing the app

- **The project is generated from `project.yml`** by [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you **add or rename Swift files**, or change settings in `project.yml`, run:

  ```bash
  brew install xcodegen   # once
  xcodegen
  ```

  This regenerates `HourTracker.xcodeproj` and resets the Team you picked in step 2. To make the team stick, add your team ID to `project.yml` under `targets → HourTracker → settings → base`:

  ```yaml
  DEVELOPMENT_TEAM: ABCDE12345
  ```

  (You can find the ID in Xcode → Settings → Accounts.)
- **App name:** change `CFBundleDisplayName` in `project.yml`, then run `xcodegen`.
- **Server address:** `HourTracker/Core/Config.swift`.
- **Colors and fonts:** `HourTracker/UI/Theme.swift`.

## Checking the server rules still work

After changing anything in `server/`, run the automated checks (they start a throwaway server, so they don't touch your data):

```bash
cd server && python3 smoke_test.py
```

Every line should say `PASS`.
