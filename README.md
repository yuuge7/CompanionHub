<div align="center">

# Companion Hub

**An offline-first Android companion for gacha games.**

Energy timers, pity forecasting, daily-task tracking, a floating in-game
checklist and a home screen widget — for
**Honkai: Star Rail**, **Wuthering Waves**, **Reverse: 1999** and
**Neverness to Everness**.

100% on-device · no account · no network · no telemetry

</div>

---

## Contents

- [Features](#features)
- [How it works](#how-it-works)
- [Project layout](#project-layout)
- [Getting started](#getting-started)
- [Building a release](#building-a-release)
- [Release signing & keeping your key](#release-signing--keeping-your-key)
- [Automated releases (CI)](#automated-releases-ci)
- [Tuning game data](#tuning-game-data)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### ⚡ Energy & overflow timers
Live per-game regeneration projection with distinct normal and overflow rates
(HSR 300 → 2400 @ 6/18 min, WuWa 240 → 480 @ 6/12 min, Re:1999 & NTE 240 @
6 min). Cap warnings fire 30 minutes ahead. **Sleep Safe** suppresses night-time
alarms and instead sends a single silent morning summary reporting the overflow
accrued overnight.

### 🎲 Pity forecaster
Exact probability of securing the featured character given current pity,
guarantee state and projected currency income to a target date — a soft-pity
convolution model with 50/50 handling for HSR/WuWa/Re:1999 and straight
guarantee for NTE.

### ✅ Daily tasks & floating overlay
Per-game daily checklists that auto-clear at each game's server reset
(HSR/WuWa 06:00, NTE 08:00, Re:1999 13:00, device-local). A draggable
**floating bubble** (`flutter_overlay_window`) expands into the checklist over
any running game so you can tick dailies without alt-tabbing.

### 📅 NTE weekly dashboard
City Tycoon stamina tracking, three weekly bosses plus Realm of Greed, a
Monday-05:00 reset and a Sunday-evening burn warning when limits are unfinished.

### 🏠 Home screen widget
A native Kotlin widget that converts raw premium currency into pull counts and
shows each game's live energy with a progress bar **and a fill ETA — both the
time remaining and the exact clock time energy hits the cap** (then the overflow
reserve). Energy is projected natively at render time, so the numbers stay fresh
without waking the Flutter engine.

### ⚙️ Show / hide games
Any of the four games can be hidden from **Settings**. A hidden game disappears
from every tab, the overlay bubble and the widget, and fires no alerts — its
saved data is kept and restored the moment you unhide it. The widget rows
redistribute so there is never empty space.

---

## How it works

- **Offline by design** — all state lives in local [Hive](https://pub.dev/packages/hive)
  boxes (plain JSON maps, no code generation). There is no backend, no account
  and no network access.
- **State** is managed with [Riverpod](https://pub.dev/packages/flutter_riverpod).
- **Alarms** use [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications)
  + [`timezone`](https://pub.dev/packages/timezone) and are re-planned on launch,
  on state change and after reboot.
- **The overlay bubble** runs in a *second* `FlutterEngine` (entry point
  `overlayMain`) that shares the same Hive boxes and pings the main engine when
  it writes changes.
- **The widget** is driven by [`home_widget`](https://pub.dev/packages/home_widget):
  the app writes an energy *anchor* (value + timestamp) plus regen rates into
  shared preferences, and `PullWidgetProvider.kt` projects it forward on each
  periodic update.

---

## Project layout

```
lib/
  main.dart                 app entry + overlayMain (bubble engine)
  core/                     games.dart (all game constants), energy_math,
                            pity_math, reset_time, theme
  data/                     models + Hive store
  services/                 notification_service, alert_scheduler,
                            widget_service, overlay_service
  providers/                Riverpod notifiers
  screens/                  home_shell, energy, nte_weekly, pity, tasks, settings
  overlay/overlay_app.dart  floating bubble UI
android/app/src/main/
  AndroidManifest.xml       SYSTEM_ALERT_WINDOW, specialUse FGS service,
                            notification receivers, widget receiver
  kotlin/.../PullWidgetProvider.kt   native widget rendering + energy projection
  res/layout/pull_widget.xml
  res/xml/pull_widget_info.xml
test/                       math-engine + energy-flow tests
.github/workflows/          release automation
```

---

## Getting started

### Prerequisites

| Tool | Version |
|------|---------|
| [Flutter](https://docs.flutter.dev/get-started/install) SDK | 3.44.x (stable) |
| Dart | ^3.12 (bundled with Flutter) |
| JDK | 17 |
| Android SDK | platform 34+, build-tools 34+ |

Verify your toolchain with `flutter doctor`.

### Clone & run

```sh
git clone https://github.com/<your-org>/CompanionHub.git
cd CompanionHub

flutter pub get           # fetch dependencies
flutter test              # run the unit tests
flutter run               # launch on an attached device / emulator
```

On first launch, grant **Notifications + exact alarms** (Settings tab) and
**"Display over other apps"** (Tasks tab) so the floating bubble can be shown.

> App icons are generated from `assets/icon/` via
> `dart run flutter_launcher_icons` (config in `pubspec.yaml`).

---

## Building a release

```sh
flutter build apk --release      # -> build/app/outputs/flutter-apk/app-release.apk
```

If a release keystore is configured (see below) the artifact is signed with it;
otherwise the build **falls back to the debug key** so a fresh clone still
builds without any setup.

---

## Release signing & keeping your key

Release builds are signed with a keystore that is **deliberately kept out of
git**. The signing config in `android/app/build.gradle.kts` reads
`android/key.properties`; if that file is missing (fresh clone, CI without
secrets) the build transparently falls back to the debug key.

```
CompanionHub/
├── companionhub-release.jks     ← the keystore (gitignored)
└── android/
    └── key.properties           ← passwords + alias + path (gitignored)
```

`key.properties` looks like this:

```properties
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=companionhub
storeFile=companionhub-release.jks
```

> ⚠️ **Both files are ignored by git and exist only on your machine.**
> If you lose the `.jks` **you can never ship an update to an app installed with
> it** — Android rejects an APK signed by a different key. Back it up.

### 🔐 Back up the key (do this once)

Copy **both** files somewhere safe and private (password manager, encrypted
drive, private backup):

- `companionhub-release.jks`
- `android/key.properties`

Also record the key details independently:

```
Alias:  companionhub
SHA-256: EF:20:64:6A:90:4C:E7:E6:7E:8F:5F:3A:C2:4D:EC:F0:74:4B:4E:5B:18:4A:F7:BD:DB:E0:6B:87:39:F3:06:12
```

You can re-print the fingerprints any time with:

```sh
keytool -list -v -keystore companionhub-release.jks
```

### 💻 Use the same key on another machine

1. Clone the repo and run `flutter pub get`.
2. Copy your backed-up **`companionhub-release.jks`** into the **project root**.
3. Recreate **`android/key.properties`** with the same passwords/alias shown
   above (or copy your backed-up file).
4. `flutter build apk --release` — the build now signs with your original key,
   producing an APK that can update existing installs.

### 🆕 Create a brand-new key (only if you don't have one yet)

```sh
keytool -genkeypair -v \
  -keystore companionhub-release.jks \
  -alias companionhub \
  -keyalg RSA -keysize 2048 -validity 10000
```

Place the resulting `.jks` in the project root and fill in `android/key.properties`.

---

## Automated releases (CI)

[`.github/workflows/release.yml`](.github/workflows/release.yml) builds and
publishes a GitHub Release on **every push to `main`**.

- The release is named **`Companion Hub vX.Y`**, where `X.Y` is the
  **major.minor** of the `version:` field in `pubspec.yaml`
  (e.g. `version: 1.2.0+5` → **`v1.2`**).
- Bump the minor/major in `pubspec.yaml` to cut a new release entry; further
  pushes under the same `X.Y` refresh that same release in place.
- The workflow runs `flutter analyze` and `flutter test` before building.

> GitHub only executes workflow files located in **`.github/workflows/`** — that
> is why the file lives there rather than directly under `.github/`.

### CI-signed releases

The keystore is never committed, so to have CI sign releases with your real key
the workflow reconstructs it from **repository secrets**. Add these under
**Settings → Secrets and variables → Actions → New repository secret**:

| Secret name | Value |
|-------------|-------|
| `RELEASE_KEYSTORE_BASE64` | base64 of `companionhub-release.jks` (see below) |
| `RELEASE_STORE_PASSWORD` | your store password |
| `RELEASE_KEY_PASSWORD` | your key password |
| `RELEASE_KEY_ALIAS` | `companionhub` |

Produce the base64 value for the first secret with:

```sh
base64 -w0 companionhub-release.jks        # copy the single-line output
```

The workflow's **Set up release signing** step decodes these into
`companionhub-release.jks` + `android/key.properties` before building. If
`RELEASE_KEYSTORE_BASE64` is absent (for example on a fork), the step is skipped
and the build falls back to the debug key — so contributors need no secrets.

---

## Tuning game data

Every game constant — caps, regen rates, pity curves, pull costs, reset hours
and daily/weekly task lists — lives in one file:
[`lib/core/games.dart`](lib/core/games.dart). The NTE soft-pity curve and the
City Tycoon stamina formula might be wrong - no information available when I last checked. 

---

## Contributing

1. Fork and create a feature branch off `main`.
2. Set up the toolchain and run the app (see [Getting started](#getting-started)).
3. Before opening a PR, make sure the following pass:
   ```sh
   flutter analyze
   flutter test
   ```
4. Keep game-specific numbers in `lib/core/games.dart`, and match the existing
   code style (the project uses `flutter_lints`).

You do **not** need the release keystore to contribute — release builds fall
back to the debug key automatically.

---

## License

Released under the [MIT License](LICENSE).
