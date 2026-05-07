# Flow

Wispr-Flow-style dictation for macOS. Hold or tap the Fn key, speak, release/tap again, and the transcribed text gets pasted into the focused app.

- **Trigger**: Fn key
  - **Hold-to-talk**: hold Fn while speaking, release to send
  - **Tap-toggle**: tap Fn to start, tap Fn again to stop
  - The app figures out which mode you meant from press duration (>500ms = hold, <500ms = tap)
- **STT**: WhisperKit running locally (free, no API costs, runs on the Apple Neural Engine)
- **Cleanup**: not yet (Phase 2 — Claude bridge call to fix punctuation/filler)

## Install (download prebuilt)

GitHub Actions builds `Flow.app` on every push and publishes it as the `latest` release. One-liner to install on your Mac:

```bash
curl -L https://github.com/Blanketo123/flow/releases/latest/download/Flow.zip -o /tmp/flow.zip && \
  unzip -o /tmp/flow.zip -d /Applications && \
  xattr -dr com.apple.quarantine /Applications/Flow.app && \
  open /Applications/Flow.app
```

The app is unsigned (no Apple Developer account), so the `xattr` step removes Gatekeeper's quarantine flag. Without that step macOS would refuse to open it.

## Build locally (alternative)

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
cd ~/workspaces/flow
./bundle.sh
open Flow.app
```

First launch downloads the Whisper `base` model (~140MB) into `~/Library/Application Support/...` automatically.

## Permissions

On first run, macOS will prompt for:

1. **Microphone** — needed to record audio
2. **Accessibility** — needed to capture the Fn key globally and to paste into other apps

If the Fn key does nothing: open **System Settings → Privacy & Security → Accessibility**, add `Flow.app`, and toggle it on.

## How to use

1. Click into any text field (Slack, browser, terminal, anywhere)
2. **Hold Fn** and speak. Release Fn → text appears.
3. Or: **tap Fn** quickly to start recording. Speak. **Tap Fn** again to stop and paste.

Menu bar icon shows state:
- `mic` — idle
- `mic.fill` — recording
- `ellipsis.circle` — transcribing
- `hourglass` — loading model (first launch)

## Roadmap

- [ ] Cleanup pass via Claude bridge (`praktikanten-hub.vercel.app/api/claude-bridge`) for punctuation, filler removal, casing
- [ ] Choose model size from menu (`tiny`, `base`, `small`)
- [ ] Custom vocabulary
- [ ] App-aware tone (Slack vs. terminal vs. email)
