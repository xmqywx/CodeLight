<div align="center">

# CodeLight

**Your Claude Code sessions, on your iPhone.**

A companion app to [CodeIsland](https://github.com/xmqywx/CodeIsland) — monitor and control your AI coding sessions from anywhere, with Dynamic Island support.

This is a passion project built purely out of personal interest. It is **free and open-source** with no commercial intentions whatsoever. I welcome everyone to try it out, report bugs, and contribute code. Let's build something great together!

这是一个纯粹出于个人兴趣开发的项目，**完全免费开源**，没有任何商业目的。欢迎大家试用、提 Bug、贡献代码。一起把它做得更好！

[![GitHub stars](https://img.shields.io/github/stars/xmqywx/CodeLight?style=social)](https://github.com/xmqywx/CodeLight/stargazers)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-17%2B-black?style=flat-square&logo=apple)](https://github.com/xmqywx/CodeLight/releases)

</div>

---

## What is CodeLight?

**CodeIsland** lives in your Mac's notch. **CodeLight** lives in your pocket.

When you step away from your desk, CodeLight keeps you connected to your Claude Code sessions. See what Claude is doing, read the conversation, and send messages — all from your iPhone.

```
  Mac (CodeIsland)              Cloud                    iPhone (CodeLight)
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────────┐
│  Claude Code     │    │  CodeLight       │    │  📱 Session list         │
│  sessions are    │───▶│  Server          │───▶│  💬 Chat view            │
│  synced in       │    │  (self-hosted)   │    │  🏝️ Dynamic Island      │
│  real-time       │◀───│                  │◀───│  ⌨️ Send messages        │
└──────────────────┘    └──────────────────┘    └──────────────────────────┘
```

## Features

### Real-time Session Sync

See your Claude Code conversations on your iPhone as they happen. Every message, tool call, and thinking block streams to your phone in real-time.

### Dynamic Island

Your iPhone's Dynamic Island becomes a status indicator for Claude Code:

| State | What you see |
|-------|-------------|
| 🟣 Thinking | Project name + elapsed time |
| 🔵 Tool running | Tool name (e.g., "Edit main.swift") |
| 🟠 Needs approval | Tap to open and review |
| 🟢 Done | Auto-dismisses after 5 seconds |

### Send Messages

Type messages to Claude Code from your phone. Switch models (Opus / Sonnet / Haiku) and permission modes without touching your Mac.

### Self-Hosted & Private

Run your own CodeLight Server. Your data stays on your infrastructure. The server is **zero-knowledge** — it relays encrypted messages without reading them.

### QR Code Pairing

No accounts. No passwords. Scan a QR code from CodeIsland to pair your phone with your Mac. Your public key is your identity.

### Multi-Server Support

Connect to multiple CodeLight Servers — monitor sessions across different machines or environments from a single app.

## How It Works

CodeLight extends [CodeIsland](https://github.com/xmqywx/CodeIsland) with remote access:

1. **Claude Code** runs on your Mac and emits hook events
2. **CodeIsland** (Mac notch app) receives hooks and syncs session data to the CodeLight Server
3. **CodeLight Server** (self-hosted) relays encrypted messages via Socket.io
4. **CodeLight** (iPhone app) displays sessions and lets you send messages back

All communication is encrypted end-to-end. The server cannot read your messages.

## Requirements

- [CodeIsland](https://github.com/xmqywx/CodeIsland) installed on your Mac (the bridge between Claude Code and the server)
- A server to host CodeLight Server (any VPS with Node.js 20+ and PostgreSQL)
- iPhone running iOS 17+

## Quick Start

### 1. Deploy the Server

```bash
git clone https://github.com/xmqywx/CodeLight.git
cd CodeLight/server
npm install

# Configure
cp .env.example .env
# Set DATABASE_URL, MASTER_SECRET (random 64-char hex), and PORT

# Database setup
npx dotenv -e .env -- prisma migrate dev --name init

# Run
npm start
```

Set up a reverse proxy (Nginx) with SSL for production. See [Server Configuration](#server-configuration) for details.

### 2. Build the iPhone App

```bash
cd CodeLight/app
open CodeLight.xcodeproj
```

- Select your development team for both targets
- Connect your iPhone, press **⌘R**
- Enter your server URL on first launch

### 3. Connect CodeIsland

CodeIsland's sync module connects your Mac to the server automatically. On the `feature/codelight-sync` branch, CodeIsland will:

- Authenticate with the server on launch
- Sync all active Claude Code sessions
- Relay messages in real-time

## Project Structure

```
CodeLight/
├── server/              # Relay server (Fastify + Socket.io + PostgreSQL)
├── app/                 # iPhone app (SwiftUI + ActivityKit)
│   ├── CodeLight/       # Main app target
│   └── CodeLightWidget/ # Dynamic Island widget extension
├── packages/            # Shared Swift Packages
│   ├── CodeLightProtocol/   # Message types
│   ├── CodeLightCrypto/     # E2E encryption (CryptoKit)
│   └── CodeLightSocket/     # Socket.io client wrapper
└── DESIGN.md            # Full design specification
```

## Server Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `MASTER_SECRET` | Yes | Random hex string for JWT signing |
| `PORT` | No | Server port (default: 3006) |
| `APNS_KEY_ID` | No | Apple Push Notification key ID |
| `APNS_TEAM_ID` | No | Apple Developer Team ID |
| `APNS_KEY` | No | Base64-encoded .p8 private key |
| `APNS_BUNDLE_ID` | No | App bundle ID for push |

### Nginx Example

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3006;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400s;
        proxy_buffering off;
    }
}
```

## Security

| Layer | How |
|-------|-----|
| **Identity** | Ed25519 public key — no accounts, no passwords |
| **Transport** | TLS (HTTPS/WSS) |
| **Messages** | E2E encryption ready (ChaChaPoly via CryptoKit) |
| **Server** | Zero-knowledge relay — stores only ciphertext |
| **Keys** | Stored in iOS/macOS Keychain, never exported |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Server | Node.js, TypeScript, Fastify 5, Socket.io, Prisma, PostgreSQL |
| iOS App | Swift, SwiftUI, ActivityKit, WidgetKit |
| Encryption | Apple CryptoKit (ChaChaPoly, Curve25519) |
| Mac Bridge | [CodeIsland](https://github.com/xmqywx/CodeIsland) + Socket.io Swift |

## Roadmap

- [ ] QR code camera scanning (currently manual URL entry)
- [ ] Permission approval from phone
- [ ] Rich message rendering (markdown, code blocks)
- [ ] APNs push notifications for background alerts
- [ ] Tool result visualization
- [ ] Chat history search

## Related Projects

| Project | Description |
|---------|-------------|
| [CodeIsland](https://github.com/xmqywx/CodeIsland) | macOS notch companion for Claude Code — **required** for CodeLight to work |
| [cmux](https://cmux.io) | Modern terminal multiplexer — recommended for multi-session management |

## Contributing

Contributions are welcome!

1. **Report bugs** — [Open an issue](https://github.com/xmqywx/CodeLight/issues)
2. **Submit a PR** — Fork, branch, code, PR
3. **Suggest features** — Open an issue tagged `enhancement`

## 参与贡献

欢迎参与！

1. **提交 Bug** — 在 [Issues](https://github.com/xmqywx/CodeLight/issues) 中描述问题
2. **提交 PR** — Fork 本仓库，新建分支，修改后提交 Pull Request
3. **建议功能** — 在 Issues 中提出

## Contact / 联系方式

- **Email**: xmqywx@gmail.com

## License

MIT — free for any use.
