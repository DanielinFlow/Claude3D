# Claude3D — Setup

A 3D virtual office for Claude-powered agents. Built on the Claude3D base
(OpenClaw runtime provider, multi-floor architecture) with the Hermes3D
visual/audio/conversation polish ported in. There is no Hermes runtime in
this build: agents connect through OpenClaw gateways only.

## Two floors

| Floor | Binds to | Default URL |
|---|---|---|
| **Local** (`openclaw-ground`) | OpenClaw Gateway on the desktop PC | `ws://localhost:18789` (override: `NEXT_PUBLIC_LOCAL_GATEWAY_URL`) |
| **VPS** (`openclaw-vps`) | OpenClaw Gateway on the Hetzner VPS over Tailscale | unset (set `NEXT_PUBLIC_VPS_GATEWAY_URL=wss://<host>.<tailnet>.ts.net`) |

Mobile does not run its own gateway: pair the phone as a device/node against
the desktop gateway, and its agents appear on the Local floor alongside the
desktop agents.

Both floors use the `openclaw` adapter but keep their own gateway binding.
Per-floor URLs persist in studio settings (`officeFloors[<floorId>].gatewayUrl`),
and the Studio proxy remembers which auth token belongs to which gateway URL
(`gateway.urlTokens`, server-side only — tokens never reach the browser), so
switching floors reconnects against the right gateway with the right token.

## First-time setup

1. **Desktop gateway** — install/run an OpenClaw Gateway on the PC if one is
   not already running: `npx openclaw gateway run --bind loopback --port 18789`.
2. **VPS gateway** — already runs on the VPS. Read its token with
   `openclaw config get gateway.auth.token` on the VPS.
3. **Env** — copy `.env.example` to `.env`, set `NEXT_PUBLIC_VPS_GATEWAY_URL`.
   For production also set `UPSTREAM_ALLOWLIST=localhost,<host>.<tailnet>.ts.net`
   (the proxy refuses un-allowlisted upstreams in production).
4. **Build & run** — Node 20+: `npm install && npm run build && npm start`
   (or `npm run dev` for development).
5. **Connect Local floor** — pick the Local floor, connect. First connect
   needs device approval on the desktop gateway host:
   `openclaw devices approve --latest`.
6. **Connect VPS floor** — pick the VPS floor, enter the `wss://` URL and the
   VPS gateway token in the connect screen, connect, then approve the device
   on the VPS the same way. After this one-time step, floor switching restores
   each floor's gateway and token automatically.

## Daily start

Two processes need to be alive: the OpenClaw gateway and the Studio app. One
command handles both:

```bash
./scripts/start-office.sh
```

It reuses whatever is already running (gateway, app), installs dependencies on
first run, picks another port if 3000 is taken, waits until the office answers,
and opens the browser. Logs land in `/tmp/claude3d-logs/`.

Handy as an alias:

```bash
echo 'alias office="$HOME/Claude3D/scripts/start-office.sh"' >> ~/.bashrc
```

### Gateway as a service (optional)

To stop babysitting a terminal for the gateway, install it as a systemd user
service — it then starts at login and restarts on failure:

```bash
./scripts/install-gateway-service.sh
```

Stop any hand-started gateway first, or the service cannot bind the port.

```
Status   systemctl --user status openclaw-gateway
Logs     journalctl --user -u openclaw-gateway -f
Remove   ./scripts/install-gateway-service.sh --uninstall
```

To keep it running when you are not logged in: `sudo loginctl enable-linger $USER`.

## Ported polish (from Hermes3D)

- Cinematic rendering: perspective camera, HDRI image-based lighting, sun rig,
  depth fog, daylight drift, post-processing (AO, bloom, vignette, filmic tone
  mapping, SMAA, follow-cam depth of field) — `systems/atmosphere.tsx`.
- Graphics quality presets (low/balanced/ultra) with software-renderer
  auto-detection, persisted per browser — settings panel → Graphics quality.
- Procedural PBR textures for office objects — no bundled image assets.
- Agent conversation huddles: agents replying in the same window gather into a
  circle, take speaking turns, and murmur softly (synthesized chatter, unlocked
  on first pointer interaction).
- Scene error boundary: transient WebGL startup failures retry instead of
  white-screening.
- Gateway URL diagnostics in the connect screen (e.g. warns when `wss://` is
  pointed at a tailnet port Tailscale serves as plain HTTP).

## `office.speech` events

Turns driven from other clients (desktop app, TUI, CLI) reach the office feed
via `office.speech` gateway events (`src/lib/office/officeSpeech.ts` parses
them; the screen feeds them into the same reply feed the 3D scene watches, so
remote-driven turns raise speech bubbles and huddles like local ones). The
OpenClaw gateway does not emit this event by itself: it needs a gateway-side
publisher (the OpenClaw equivalent of Hermes3D's office-bridge plugin,
publishing `{agentId, name, text, atMs}` under event `office.speech`).
Until such a publisher exists, turns driven locally in the office UI still
animate normally through the regular reply flow.
