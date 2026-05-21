# CardShow Pro — Setup

Plug your iPhone into your Mac via USB-C and run **one command**. The app installs and launches. The backend starts itself.

## Prerequisites

- macOS with **Xcode 16+** installed (Mac App Store, free)
- **Python 3.12+** (`brew install python@3.12`)
- A **free Apple ID** added to Xcode (Xcode → Settings → Accounts → "+" → Apple ID)
- An **iPhone** running iOS 17+, plugged in via USB-C and "trusted"

## One-command install

```bash
git clone https://github.com/JeremyEltho/card-show-v2.git
cd card-show-v2
./scripts/run-on-device.sh
```

That's it. The script will:
1. Detect your Mac's LAN IP
2. Start the FastAPI backend (creates Python venv on first run)
3. Ask for your **Apple Team ID** and **Bundle ID** on first run (saved to `.cardshow.config`, gitignored)
4. Inject the backend URL into the app's Info.plist
5. Build and code-sign the app
6. Install on whichever iPhone is plugged in
7. Launch it

### Finding your Team ID

Open Xcode → Settings → Accounts → click your Apple ID. Your Team ID is the 10-character code next to your name.

Or, simpler: open `ios/CardShowPro.xcodeproj`, click the project, then **Signing & Capabilities** — the Team dropdown shows your IDs.

### Bundle ID

Apple requires bundle IDs to be globally unique per Apple ID. The script suggests `com.cardshowpro.<yourusername>` as a safe default. Accept it, or pick anything that starts with `com.<yourname>.`.

---

## Simulator instead

If you don't want to plug in a phone:

```bash
./scripts/run-on-device.sh --simulator
```

Opens iPhone 17 Pro simulator and installs the app there. No code signing needed.

> Note: the simulator has no camera. You can still test the UI and the search/inventory/today screens, but actual card scanning requires a real device.

---

## What if the script fails?

**"No iPhone detected via USB-C"** — Make sure the phone is unlocked, plugged in, and you tapped "Trust This Computer" the first time you connected it.

**"Build failed: provisioning"** — Your Apple ID isn't added to Xcode. Open Xcode → Settings → Accounts → "+" and sign in.

**"Bundle ID is already in use"** — Someone else's account has claimed `com.cardshowpro.<youruser>`. Edit `.cardshow.config` and change `BUNDLE_ID` to something else (e.g., `com.<yourname>.scanner`).

**App opens but says "Could not connect to server"** — Wi-Fi changed networks since install. Open the app → **Settings** tab → **Connection** → **Edit** → paste new URL → **Test**. The new IP is shown in your Mac's System Settings → Wi-Fi → "Details" → IP Address.

---

## Manual setup (if you want to skip the script)

```bash
# Backend
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
alembic upgrade head
python seed.py
uvicorn main:app --host 0.0.0.0 --port 8000

# Mac IP for the app to talk to
ipconfig getifaddr en0     # → e.g., 192.168.1.42

# Open Xcode, set signing, set bundle ID, click Run
open ios/CardShowPro.xcodeproj
```

In the running app, open **Settings → Connection → Edit** and paste `http://<your-mac-ip>:8000/api/v1`. Tap **Test** — should show "CONNECTED" in green.

---

## Architecture

```
iOS App  (USB-C plugged-in iPhone, iOS 17+)
  │
  ▼  HTTPS / JWT — phone talks to Mac over Wi-Fi
FastAPI Backend  (on Mac, port 8000)
  │
  ├─ SQLite        (./backend/pokescan.db)
  ├─ pokemontcg.io (card metadata, lazy-cached)
  └─ JustTCG       (pricing, optional)
```

### Three tabs

| Tab    | What it does                                              |
|--------|-----------------------------------------------------------|
| Scan   | Camera + name capture + buy/sell logging                  |
| Stock  | Cards you currently have to sell (one-tap "SELL")         |
| Today  | Buys / Sells / Net for the current show                   |

### Scan confidence tiers

| Confidence | UX                                  |
|-----------:|-------------------------------------|
|     ≥ 95% | Auto-log + 3s "Undo" banner          |
|   80–94%  | Confirmation sheet — vendor confirms |
|    < 80%  | Manual search field                  |

---

## Running tests

```bash
cd backend && source .venv/bin/activate
pytest tests/ -v       # 35 tests, all green

# Scan accuracy test (uses Test-Data/ folder of real card images)
python ../scripts/test_scan.py
```

---

## Re-running

After the first install, re-running is the same command:

```bash
./scripts/run-on-device.sh
```

It will skip setup steps that are already done. Backend keeps running in background — `kill $(lsof -ti:8000)` to stop it.

The free Apple ID re-sign **expires after 7 days**. Re-run the script to refresh.
