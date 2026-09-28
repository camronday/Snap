# Snap

Snap is a lightweight, sandboxed menu bar app for macOS that captures a region or window, annotates it, lifts text with Live Text, and records short GIFs, all without ever touching the network.

## Features

- Region capture, drag out an area of the screen and copy or save it
- Window capture, pick any on-screen window via Space
- Delayed capture, 3 or 5 second countdown before the shot is taken
- Annotation tools: arrows, rectangles, freehand, highlight, blur, pixelate and callouts
- Live Text: select or click text and links straight off the captured image
- GIF recording of a chosen region, copied to the clipboard when it finishes
- Annotate Clipboard Image: opens whatever image is already on your clipboard in the same annotation tools

## Install

### Mac App Store

*Coming soon* - submission in progress.

### Build from source

Requirements: macOS 26, Xcode (the full app, not just the Command Line Tools), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```
git clone https://github.com/camronday/Snap.git && cd Snap && ./scripts/install.sh
```

This generates the Xcode project, builds a Release configuration, and installs Snap to `/Applications`.

### First launch

Snap needs Screen Recording access to capture your screen. The first launch opens a window explaining this; grant it in System Settings > Privacy & Security > Screen Recording, then relaunch Snap.

## Shortcuts

| Action | Default shortcut |
| --- | --- |
| Capture Region | ⌃⇧S |
| Record GIF (start/stop) | ⌃⇧G |

Both are rebindable from Settings > Shortcuts. Window capture, delayed capture and clipboard annotation are menu-only.

## Settings

- Launch at login
- Copy at full Retina resolution
- GIF maximum recording duration

## Security and privacy

Snap is sandboxed and runs under the hardened runtime. It has no network entitlement at all, it cannot make or receive any network connection, and the only permission it asks the system for is Screen Recording. Nothing captured leaves your Mac except what you explicitly copy or save yourself. Its one dependency is audited and pinned to an exact commit (see Acknowledgements).

## Updating

```
git pull && ./scripts/install.sh
```

## Uninstall

```
./scripts/uninstall.sh
```

Removes the app, its preferences, and its Screen Recording permission grant.

## Acknowledgements

KeyboardShortcuts, Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com), MIT License.
