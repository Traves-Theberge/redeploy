# pideploy — Project Plan

> Run a CLI in any git repo → every push builds the app with Docker on a
> Raspberry Pi, it appears in Portainer, and it's reachable anywhere over
> Tailscale. Beautiful, configurable, and AI-ready.

Status legend: ✅ done · 🟡 in progress · ⬜ todo

---

## 1. End-to-end vision

```
 ┌────────────┐   git push    ┌──────────┐   self-hosted runner   ┌──────────────┐
 │ your dev   │ ────────────▶ │  GitHub  │ ─────(outbound)──────▶ │ Raspberry Pi │
 │ machine    │               │ Actions  │   builds + compose up  │  (this host) │
 └────────────┘               └──────────┘                        └──────┬───────┘
        ▲                                                                  │
        │  pideploy init / deploy / status / serve                        │ shares Docker engine
        │                                                                  ▼
        │                                                          ┌──────────────┐
        └────── https://<host>.ts.net  ◀── tailscale serve ──────  │  Portainer   │
                  (tailnet-only, TLS)                               │ sees stacks  │
                                                                    └──────────────┘
```

**Key design decisions**
- **One runner per repo**, as a *user* systemd service (`pideploy-runner@<owner-repo>`).
  Personal GitHub accounts can't share a runner across repos.
- **Outbound-only**: the runner dials GitHub, so the Pi needs no inbound ports.
  GitHub webhooks *cannot* reach a tailnet-only Pi — never rely on them.
- **Portainer integration is implicit**: runner and Portainer share one Docker
  engine, so `docker compose up` stacks show up in Portainer automatically.
  Compose `name:` = the stack name shown there.
- **Exposure** via `tailscale serve --https=443 <port>`; apps bind `127.0.0.1` only.
- **Secrets never in git**: `.pideploy.conf` holds only port/name/branch; `.env`
  is gitignored; real secrets live in GitHub Actions secrets or Portainer env.

---

## 2. Repository layout

```
pideploy/
├── pideploy              ✅ the CLI (single bash file, dependency-light)
├── README.md             ✅ headline doc (prereqs + setup walk-throughs)
├── PLAN.md               ✅ this file
├── LICENSE               ✅ MIT (copyright "pideploy contributors", PII-free)
├── install.sh            ✅ installer (symlink into ~/.local/bin + doctor)
├── .gitignore            ✅
└── tests/
    ├── run.sh            ✅ hermetic suite (65 checks, all green)
    └── mocks/            ✅ gh, docker, tailscale, systemctl, loginctl
```

---

## 3. Command surface

| Command | Status | Notes |
|---------|--------|-------|
| `pideploy` (menu) | ✅ | numbered interactive menu |
| `init` | ✅ | scaffold + runner + `.pideploy.conf` + push |
| `deploy` | ✅ | workflow_dispatch, else empty commit |
| `status` | ✅ | runners + containers + serve + linger |
| `serve` / `unserve` | ✅ | Tailscale HTTPS expose |
| `logs` | ✅ | tail container logs |
| `config` | ✅ | list/get/set/edit; global + per-repo precedence |
| `rm` | ✅ | deregister this repo's runner |
| `doctor` | ✅ | prerequisite/health check |
| `agent` / `--agent` | ✅ | full operating manual for AI agents |
| `version` / `help` | ✅ | |

---

## 4. Done

- ✅ Core CLI with all commands above
- ✅ Config system: built-in → global (`~/.config/pideploy/config`) → repo
  (`.pideploy.conf`) → flags
- ✅ Per-repo runner as user systemd service (no root; one-time `enable-linger`)
- ✅ Stack detection for Dockerfile (node / python / go / static fallback)
- ✅ `.pideploy.conf` generation (secret-free, version-controlled)
- ✅ `.gitignore` auto-protects `.env`; workflow omits `pull_request` (public-repo safety)
- ✅ AI-ready `--agent` manual
- ✅ Beautiful output primitives (banner, box, section, glyphs, spinner; NO_COLOR aware)
- ✅ Hermetic test suite — 64 checks, all passing
- ✅ PII scrub verified (no username/email/tailnet/IP/token hardcoded)

---

## 5. Outstanding TODO

### Docs & packaging
- ✅ **README.md** — what it is, 60-second quick start, full setup walk-throughs
  (Tailscale / Portainer / GitHub / host prep), architecture, command + config
  reference, security model, troubleshooting, AI-ready section
- ✅ **LICENSE** (MIT, PII-free copyright)
- ✅ **install.sh** (symlink + PATH check + doctor)
- ✅ `.gitignore` for the repo itself

### CLI polish (consistency pass)
- ✅ Unified visual language — `box` cards for command intros, `▸ section` for every
  phase, `✓/•/!/✗` line items, `field` summaries, green `╰─` footer
- ✅ `box` auto-sizes to content (no more truncation)
- ✅ `init` returns 0 on success (was leaking a non-zero from a trailing `&&`)
- ⬜ Optional arrow-key menu (fallback to numbered) — nicer but must stay portable

### Features
- ⬜ `pideploy setup` — one-time host bootstrap (enable-linger, tailscale operator,
  verify Portainer) so new users run a single command
- ⬜ **Multi-app serve**: `tailscale serve --https=443 <port>` maps the whole root,
  so a second app collides. Add path-based serve (`--set-path /app`) or per-app
  subdomains. **Known limitation today: one served app per host root.**
- ⬜ `pideploy open` — print/launch the app's tailnet URL
- ⬜ Optional Portainer **API** integration (create a true Git stack) for users who
  want Portainer to own the deploy lifecycle instead of the runner
- ⬜ Org-level runner mode (one shared runner for many repos under a GitHub org)
- ⬜ Rollback helper (`pideploy rollback` → redeploy previous image/tag)

### CI / quality
- ⬜ GitHub Actions workflow running `tests/run.sh` on push/PR (ironic but needed)
- ⬜ `shellcheck` clean pass in CI
- ⬜ Live smoke test on a real throwaway repo (mocked suite is green; real run pending)

---

## 6. Outstanding tests

Current suite: **64 checks** across unit / config / CLI / agent / integration / guards.

To add:
- ⬜ `logs` command (needs a non-following test mode or a mock that exits)
- ⬜ `config edit` (EDITOR stub)
- ⬜ `serve` operator-denied → sudo fallback path
- ⬜ `doctor` failure paths (simulate missing `gh` / not in docker group / linger off)
- ⬜ Multi-app serve collision behavior (once feature exists)
- ⬜ `unserve` removes the *specific* port mapping (when multi-app lands)
- ⬜ `init` when Dockerfile/compose already exist (keep-existing branch) — partial
- ⬜ Menu dispatch routing (drive choices via piped stdin)
- ⬜ `--no-color` / `NO_COLOR` produces zero ANSI in all command outputs
- ⬜ `shellcheck` as a test step
- ⬜ install.sh idempotency test

---

## 7. Known limitations (document in README)

1. **One served app per host root** (see multi-app serve TODO).
2. **Per-repo runners** on personal accounts — N repos = N runner services.
3. **Self-hosted runner + public repo** requires discipline: never add
   `pull_request` triggers; the generated workflow already omits them.
4. Requires the host to be the deploy target (runner, Docker, Tailscale all local).

---

## 8. Definition of done (v1.0 public release)

- [ ] README that a stranger can follow from zero to first deploy
- [ ] LICENSE + install.sh + repo .gitignore
- [ ] CLI consistency pass complete
- [ ] CI green (tests + shellcheck) on GitHub
- [ ] One real end-to-end deploy verified on hardware
- [ ] Repo flipped public, PII-free (verified)
