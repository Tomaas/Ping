# Ping

A macOS menu bar app that shows your network latency and packet loss at a glance.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)

## Features

- Live ping latency and packet loss in the menu bar, updated every second
- Red dot indicator when latency or packet loss exceeds your thresholds
- Statistics with 5-minute, session, and all-time views
- Configurable host, latency threshold, and packet loss threshold
- Launch at login
- Zero dependencies

## Screenshot

```
  12ms (0%)          <- menu bar
  ┌─────────────────┐
  │ Settings...   ⌘,│
  │ Statistics      │
  │─────────────────│
  │ Quit Ping     ⌘Q│
  └─────────────────┘
```

## Install

Download the latest release and unzip to `/Applications`:

```bash
curl -L https://github.com/Tomaas/Ping/releases/latest/download/Ping.zip -o /tmp/Ping.zip && unzip -o /tmp/Ping.zip -d /Applications
```

Or grab `Ping.zip` from the [Releases](https://github.com/Tomaas/Ping/releases) page.

## Build from source

Open `Ping.xcodeproj` in Xcode and run (⌘R). Requires macOS 14+.

The app runs as a menu bar item with no dock icon.

## Release

Push a version tag to create a new GitHub Release automatically:

```bash
git tag v1.x.x
git push origin v1.x.x
```

A GitHub Actions workflow builds the app and uploads `Ping.zip` to the release.

## How it works

Pings the configured host once per second using `/sbin/ping -c 1`. Parses the response time from stdout. Tracks a rolling 10-ping buffer for the menu bar packet loss display, and accumulates stats for the statistics view.

## License

MIT
