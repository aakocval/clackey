# Security

Clackey listens to your keyboard, so it is designed to do as little as possible with that access:

- It reads only the key code and whether a key went up or down, to choose a sound. Nothing is recorded, logged, stored or sent.
- It runs in Apple's **App Sandbox** with no extra entitlements: no network, no microphone, and no file access outside its own container.
- It asks for **Input Monitoring** only, never Accessibility, so it can't type or control your Mac.
- macOS hides password fields (Secure Input) from all apps, Clackey included.
- It has no third-party dependencies.

You can check all of this in [`KeyTap.swift`](Sources/Clackey/KeyTap.swift) and [`Clackey.entitlements`](Resources/Clackey.entitlements).

## Verifying a download

Each release lists the SHA-256 of its zip. To check it:

```bash
shasum -a 256 ~/Downloads/Clackey-*.zip
```

## Reporting a vulnerability

Please use [private vulnerability reporting](https://github.com/aakocval/clackey/security/advisories/new)
rather than a public issue.
