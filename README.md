<p align="center">
  <img src="docs/logo.png" width="160" alt="Clackey logo">
</p>

<h1 align="center">Clackey</h1>

<p align="center">Mechanical keyboard sounds for your MacBook. Free, open source, menu-bar only.</p>

<p align="center"><a href="https://aakocval.github.io/clackey/"><b>▶ Try it in your browser</b></a>: type and hear the real sounds, nothing to install.</p>

Every keystroke, anywhere in macOS, plays a real mechanical switch sound, and mouse or trackpad
clicks get a click too. Fast typing overlaps naturally, and each press varies a little in pitch,
volume and sample, so it never sounds robotic.

- **2 built-in packs, recorded from real keyboards:** Gateron Red (default) and Cherry MX Red, both smooth linear switches
- **Mouse & trackpad clicks:** clicks and taps make a real mouse-click sound (can be turned off)
- **Spatial audio:** keys on the left of the keyboard play on the left, right on the right
- **Tone control:** one slider from deep/thocky to bright/clacky
- Volume, on/off toggle, Launch at Login
- ~3 ms output buffer for low latency, ~0% CPU and ~12 MB RAM when idle
- **Your own packs:** drop a folder of `.wav` files in and pick it from the menu
- Tiny and native (Swift, AVAudioEngine). No Electron, no network access, no analytics

Requires macOS 13 Ventura or later. Works on Apple silicon and Intel.

## Install on your Mac (about 2 minutes)

### 1. Download

1. Go to the [**Releases**](../../releases/latest) page.
2. Under **Assets**, click **`Clackey-x.y.z.zip`**.
3. Open your **Downloads** folder and double-click the zip. A **Clackey** app appears next to it.

### 2. Move it to Applications

1. Open a new Finder window (**⌘N**) and click **Applications** in the sidebar.
2. Drag **Clackey** from Downloads into **Applications**.

### 3. Open it the first time

Clackey is free and not signed with a paid Apple developer certificate, so macOS asks you to confirm once.

1. Double-click **Clackey** in Applications. macOS says it *"cannot be opened"* or *"Apple could not verify..."*. Click **Done** (or **Cancel**).
2. Open  **Apple menu › System Settings › Privacy & Security**.
3. Scroll down to **Security**. Next to *"Clackey was blocked..."*, click **Open Anyway**.
4. Enter your Mac password (or use Touch ID), then click **Open Anyway** again.

You only do this once. On **macOS 14 Sonoma or earlier** there's a shortcut: **right-click** (or Control-click)
Clackey in Applications, choose **Open**, then click **Open**.

<details>
<summary>Prefer Terminal? One command instead of steps 1–4</summary>

```bash
xattr -dr com.apple.quarantine /Applications/Clackey.app && open /Applications/Clackey.app
```
</details>

### 4. Allow Input Monitoring

Clackey needs to know when a key is pressed in order to play a sound.

1. A dialog says *"Clackey" would like to receive keystrokes from any application*. Click **Open System Settings**.
   (No dialog? Click the ⚠︎ icon in the menu bar, then **Grant Input Monitoring…**)
2. In **Privacy & Security › Input Monitoring**, turn on the switch next to **Clackey**.
3. If macOS asks, click **Quit & Reopen**.

A small **fn key icon** now appears in the menu bar at the top of your screen. Start typing and you'll hear it. 🎉

### 5. Make it yours (optional)

Click the fn key icon in the menu bar:

| Menu item | What it does |
|---|---|
| **Sounds On** | Turn all sounds on or off (⌘E while the menu is open) |
| **Volume** | Slider |
| **Tone: Deep ↔ Bright** | Left = deeper "thock", right = brighter "clack" |
| **Mouse & Trackpad Clicks** | Click sound for mouse buttons and trackpad clicks/taps |
| **Spatial Audio** | Left keys play on the left speaker, right keys on the right (best with headphones) |
| **Sound Pack** | Switch between Gateron Red, Cherry MX Red, or your own packs |
| **Launch at Login** | Start Clackey automatically when you log in |

### Troubleshooting

| Problem | Fix |
|---|---|
| Menu bar shows **⚠︎** | Input Monitoring is off. Turn it on (step 4). If it's already on, select Clackey in the list, remove it with **−**, add it again with **+**, and reopen Clackey. |
| No sound | Check that **Sounds On** is ticked, the volume slider isn't at zero, and your Mac's volume and output device are right. |
| Can't see the icon | The menu bar may be full (common on notched MacBooks). Quit some menu-bar apps or use a menu-bar manager. |
| Silent in password fields | That's on purpose. macOS hides password typing from all apps (Secure Input). |

### Uninstall

1. Click the menu bar icon and choose **Quit Clackey**.
2. Drag **Clackey** from Applications to the Trash.
3. Optional: remove it from **System Settings › Privacy & Security › Input Monitoring** (select it, click **−**).
4. Optional: delete its settings and custom packs at `~/Library/Containers/io.github.aakocval.Clackey`.

## Privacy

Clackey uses a *listen-only* event tap (`CGEventTap`) to see which key was pressed so it can pick
a sound. That is why macOS asks for Input Monitoring.

- It reads only the key code and whether the key went up or down. For mouse clicks, it reads only the
  button up/down and the cursor's horizontal position (for left/right panning).
- Nothing is recorded, logged, stored or sent. The app makes no network connections.
- Password fields use macOS Secure Input, which hides keystrokes from all event taps, so they stay silent.
- The app runs in the **App Sandbox** with no extra entitlements: no network, no microphone, and no file
  access outside its own container ([`Clackey.entitlements`](Resources/Clackey.entitlements)).
  It asks for **Input Monitoring** only, never Accessibility, so it can see key codes but cannot type or control your Mac.
- No third-party dependencies.

All the key handling is in [`KeyTap.swift`](Sources/Clackey/KeyTap.swift), about 100 lines. Please read it.

## Build from source

You need Xcode or the Command Line Tools (Swift 5.9+).

```bash
git clone https://github.com/aakocval/clackey.git
cd clackey
scripts/build_app.sh        # -> build/Clackey.app
open build/Clackey.app
```

`UNIVERSAL=1 scripts/build_app.sh zip` builds an arm64 + x86_64 app and a release zip.
To work in Xcode, open `Package.swift`.

> **Rebuilding:** builds are ad-hoc signed, so every rebuild looks like a new app to macOS. If the
> menu bar shows ⚠︎ after a rebuild, remove Clackey from Input Monitoring (the − button), add it again,
> and relaunch. You can set `SIGN_ID` to a stable signing identity to avoid this.

## Custom sound packs

Menu › Sound Pack › **Open Packs Folder**. Because the app is sandboxed, this folder is
`~/Library/Containers/io.github.aakocval.Clackey/Data/Library/Application Support/Clackey/Packs`. Then:

```
Packs/
  My Board/
    down-1.wav  down-2.wav  down-3.wav   # regular keys (required)
    up-1.wav    up-2.wav                 # key release (optional)
    space.wav                            # spacebar (optional, falls back to down)
    back.wav                             # delete keys (optional)
    return.wav                           # return/enter (optional)
```

- Name files `<category>.wav` or `<category>-<anything>.wav`. Several files per category are picked at random.
- WAV, AIFF, CAF, MP3 and M4A all work. Any sample rate, mono or stereo. Keep clips short (<200 ms) with no silence at the start.
- Safety limits: files over 10 MB, symlinks and hidden files are skipped. Clips are cut to 2 s, and each category uses at most 16 files.
- Reopen the menu to see the new pack. A user pack with the same name as a built-in one replaces it.

Want to contribute a pack? Please use recordings you made yourself or that are CC0, and say which in the PR.

## How it works

```
key press ─▶ CGEventTap (listen-only, session level)
              │ keycode + down/up (+ modifier flags)
              ▼
           KeyTap ─ maps key → down / up / space / back / return
              ▼
           SoundEngine ─ pick a random sample (never the same twice in a row)
              │          and one of 5 pre-rendered pitches (±3%)
              │          take the next of 16 voices (round-robin), pan by key position
              ▼
   16 × AVAudioPlayerNode ─▶ voice mixer ─▶ tone EQ (low/high shelf) ─▶ main mixer ─▶ speakers
```

- **No disk reads or DSP at keypress time.** Samples are decoded and pitch-shifted into `AVAudioPCMBuffer`s
  when a pack loads, so the audio thread only mixes.
- **Low latency:** the output device is asked for a 128-frame I/O buffer (~3 ms).
- **Polyphony** comes from a voice pool, so a new press never cuts off the previous one.
- **Auto-repeat is ignored** (holding a key plays one sound), and modifier keys click too.
- If macOS disables a slow tap (`tapDisabledByTimeout`), it is turned back on right away.
- **Idle:** after 30 s without typing the engine pauses (no audio callbacks at all) and resumes on the next key
  in ~5–15 ms. When sounds are turned off, the engine stops and releases the audio hardware.

### How the built-in packs were made

Each pack comes from a CC0 recording of someone typing, cut into single keystrokes by
[`scripts/slice_recording.py`](scripts/slice_recording.py):

1. Find keystroke starts (sharp jumps in loudness above the room noise).
2. Sort them into presses and releases (a release is a quieter hit 30–250 ms after a press).
3. Keep only keys with nothing else overlapping, reject any slice with a second key in its tail, and keep the most consistent ones.
4. Treat the darkest, longest-ringing presses as the spacebar.
5. Cut each slice once it has faded 30 dB, fade the edges, and even out the volume.

Make a pack from your own recording:

```bash
python3 scripts/slice_recording.py ~/Desktop/my-typing.wav "My Board" --credit "Recorded by me, CC0"
scripts/build_app.sh
```

The best input is 30+ seconds of typing with a short pause between keys, recorded close up in a quiet room.

## Project layout

```
Sources/Clackey/
  main.swift          app entry (menu-bar only, no Dock icon)
  MenuBarIcon.swift   fn-key template icon for the menu bar
  AppDelegate.swift   status item, menu, settings, permission flow
  KeyTap.swift        global listen-only keyboard tap
  SoundEngine.swift   polyphonic low-latency playback
  SoundPack.swift     pack loading + format conversion
Resources/
  Info.plist          LSUIElement app bundle template
  Clackey.entitlements  App Sandbox, nothing else
  Packs/              built-in packs (sliced recordings + CREDITS.txt)
  Mouse/              shared mouse-click sounds
  AppIcon.icns        app icon (generated by scripts/make_icon.swift)
scripts/
  build_app.sh        build + bundle + sign (+ zip)
  slice_recording.py  typing recording -> sound pack (--mouse for click sounds)
  make_icon.swift     draws the logo / app icon
  build_site.sh       assembles the browser demo with the app's sounds
site/                 browser demo (index.html, style.css, app.js)
.github/workflows/    GitHub Pages deploy for the demo
docs/logo.png         README + demo logo
```

## Browser demo

[`site/`](site/) is a small static page (no framework, no build tools) that plays the same sound files as the
app through the Web Audio API, with a MacBook-style keyboard that lights up as you type.

```bash
scripts/build_site.sh serve     # build into build/site and open http://localhost:8000
```

It deploys to GitHub Pages automatically through [`.github/workflows/pages.yml`](.github/workflows/pages.yml)
whenever the site or the sounds change. One-time setup: repo **Settings › Pages › Source: GitHub Actions**.
The build copies the sounds in from `Resources/`, so they're never duplicated in the repo.

## License

MIT. See [LICENSE](LICENSE).

## Sound credits

The built-in sounds are CC0 (public domain) recordings from [Freesound](https://freesound.org). Thank you to:

- **Mouse clicks:** ["20131209_mouse clicks_OlympusLS10_xy.wav"](https://freesound.org/people/Soundscape_Leuphana/sounds/210309/) by Soundscape_Leuphana
- **Cherry MX Red:** ["Keyboard clicking typing Cherry Red Mechanical"](https://freesound.org/people/handygaber/sounds/499773/) by handygaber (Corsair K95)
- **Gateron Red:** ["Typing on a keyboard"](https://freesound.org/people/SamsterBirdies/sounds/489422/) by SamsterBirdies
