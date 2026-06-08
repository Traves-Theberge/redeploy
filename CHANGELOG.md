# Changelog

All notable changes to **pideploy** are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet._

## [1.0.0] - 2026-06-07

First public release. `pideploy` turns any git repo into push-to-deploy on a
self-hosted Linux Docker host (built for a Raspberry Pi): on every `git push`, a
per-repo self-hosted GitHub Actions runner builds the repo's image and runs it via
`docker compose`. Apps appear in Portainer and are exposed over Tailscale HTTPS.

### Added
- **Push-to-deploy core** — `init` scaffolds a `Dockerfile` (node/python/go/static
  autodetect), `docker-compose.yml`, `.github/workflows/deploy.yml`, and
  `.pideploy.conf`; registers a per-repo runner as a user systemd service; commits
  and pushes (first deploy). The runner dials GitHub **outbound**, so the host needs
  no inbound ports and works on a tailnet-only network.
- **Label-based routing** — deploys are routed to the host by GitHub runner label
  (no IP/SSH/target config). `runner_label` selects a specific host when you have many.
- **Host-scoped config** (`~/.config/pideploy/config`) reused by every repo, with
  `config template` → a committed `config.example` (placeholders); precedence is
  flags → per-repo `.pideploy.conf` → host config → built-in.
- **`onboard <repo>`** — clone a repo onto the host and `init` it in one step.
- **Port registry** — `init` auto-assigns a distinct, stable port per repo
  (`~/.pideploy/ports`); explicit `--port` collisions fail; `ports` lists, `rm` frees.
  Compose sets `PORT` so apps listen on the assigned port.
- **Secrets via `.env`** — a local `.env` (source of truth) is synced to a GitHub
  Actions secret (`gh secret set`); the workflow recreates it on the runner and wipes
  it after. `.env` is never committed. `env` re-syncs after edits.
- **Multi-app serve** — `serve` is path-based by default (`tailscale serve --set-path`),
  so many apps coexist at `https://<host>/<app>`; `--port-mode` serves at
  `https://<host>:<port>/` for apps that can't handle a sub-path. `unserve` removes one route.
- **`url` / `open`** — print (or open) an app's endpoint URL.
- **`status`** (runners, stacks, serve routes, linger, deploy target), **`deploy`**
  (trigger now), **`logs`**, **`setup`** (host prep), **`doctor`** (prereq check).
- **AI-ready** — `--agent` (operating manual), `--skill` (installable Claude Code
  skill), `AGENTS.md`, and per-command `help`. Plain output contract: data→stdout,
  diagnostics→stderr, exit codes 0/1/2, `--json` on data commands, never prompts.
- **Quality** — 209-check hermetic test suite + `shellcheck`, both run in CI on every
  push/PR. MIT licensed. Verified end-to-end on real hardware (fresh repo → live app →
  push-to-deploy → clean teardown), with no secret leakage in public Actions logs.

[Unreleased]: https://github.com/Traves-Theberge/pideploy/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Traves-Theberge/pideploy/releases/tag/v1.0.0
