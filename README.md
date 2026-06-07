<div align="center">

```
        _     _            _
  _ __ (_) __| | ___ _ __ | | ___  _   _
 | '_ \| |/ _` |/ _ \ '_ \| |/ _ \| | | |
 | |_) | | (_| |  __/ |_) | | (_) | |_| |
 | .__/|_|\__,_|\___| .__/|_|\___/ \__, |
 |_|                |_|            |___/
```

**Turn any git repo into a push-to-deploy app on your own Raspberry Pi.**

`git push` → builds with Docker on your Pi → shows up in Portainer → reachable anywhere over Tailscale.

[Quick start](#-60-second-quick-start) · [Setup](#-prerequisites--setup) · [How it works](#-how-it-works) · [Commands](#-command-reference) · [Security](#-security-model) · [AI-ready](#-ai-ready)

![shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![tests](https://img.shields.io/badge/tests-101%20passing-32CD32)
![license](https://img.shields.io/badge/license-MIT-blue)
![self-hosted](https://img.shields.io/badge/self--hosted-Raspberry%20Pi-C51A4A?logo=raspberrypi&logoColor=white)

</div>

---

## What is this?

`pideploy` is a single, dependency-light CLI that gives you **your own Heroku/Vercel on hardware you own**. You run one command inside a repo, and from then on every `git push` builds your app and deploys it — privately, over your Tailscale network, visible and manageable in Portainer.

No cloud bill. No exposing ports to the internet. No webhooks poking holes in your network. Just `git push`.

The CLI is **plain, non-interactive, and scriptable** — data on stdout, progress on stderr, stable exit codes, and `--json` on every data command. Great for you in a terminal and great for AI agents.

```console
$ cd my-app
$ pideploy init --port 8080
pideploy: repo=you/my-app app=my-app port=8080 branch=main runner=pi-you-my-app   # stderr
pideploy: wrote Dockerfile
pideploy: runner pi-you-my-app installed and started
pideploy: pushed (first deploy starting)
repo=you/my-app                                                                    # stdout
app=my-app
port=8080
runner=pi-you-my-app
runner_registered=true
pushed=true

$ pideploy serve 8080
https://your-pi.your-tailnet.ts.net/        # the URL is the only thing on stdout

$ pideploy status --json
{"runners":[{"name":"you-my-app","active":true}],"stacks":[{"name":"my-app","status":"Up","ports":"127.0.0.1:8080->8080/tcp"}],"serve":["https://your-pi.your-tailnet.ts.net/"],"linger":true}
```

That's the whole workflow. Edit code, `git push`, done.

---

## ✨ Why it's different

- **Push-to-deploy, fully private.** The deploy path is GitHub Actions → a self-hosted runner on *your* Pi. Your Pi never needs an inbound port; the runner dials out.
- **Works behind Tailscale.** Because nothing inbound is required, your Pi can live entirely on your tailnet. Apps get real HTTPS via `tailscale serve`.
- **Portainer-native.** The runner and Portainer share one Docker engine, so every deployed app shows up in Portainer automatically — logs, restarts, the works.
- **Plain & scriptable.** No colors, boxes, or prompts. Data → stdout, diagnostics → stderr, exit codes `0/1/2`, and `--json` on every data command.
- **Configurable.** Global defaults + per-repo `.pideploy.conf`, overridable by flags.
- **AI-ready, three ways.** `pideploy --agent` prints a full operating manual; `pideploy --skill` emits a ready-to-install Claude Code skill; `pideploy help <command>` documents every option.

---

## 🚀 60-second quick start

> Assumes the [prerequisites](#-prerequisites--setup) below are done (Tailscale, Portainer, GitHub, host prep). First time? Do those once, then this is all you ever run.

```bash
# 1. install
git clone https://github.com/<you>/pideploy && cd pideploy
./install.sh                       # symlinks `pideploy` into ~/.local/bin

# 2. verify your machine is ready
pideploy doctor

# 3. in any repo with a GitHub remote:
cd ~/code/my-app
pideploy init                      # scaffold + runner + first deploy
pideploy serve 8080                # expose it over Tailscale HTTPS
```

From then on: **`git push` deploys.** To redeploy without code changes, `pideploy deploy`.

---

## 📦 Prerequisites & setup

`pideploy` orchestrates four things on **one Linux host** (designed for a Raspberry Pi, works on any Linux box): **Docker + Portainer**, **Tailscale**, **GitHub (`gh`)**, and a **user systemd** service for the runner. Set each up once.

Run `pideploy doctor` at any point — it checks every prerequisite and tells you exactly what's missing.

<details open>
<summary><b>1. Docker + Portainer</b> — the engine and the dashboard</summary>

<br>

Install Docker and add yourself to the `docker` group (so deploys don't need `sudo`):

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"      # log out/in for this to take effect
```

Run **Portainer**, bound to localhost (you'll reach it over Tailscale, not the LAN):

```bash
mkdir -p ~/apps/portainer/data
docker run -d --name portainer --restart unless-stopped \
  -p 127.0.0.1:9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v ~/apps/portainer/data:/data \
  portainer/portainer-ce:latest
```

> 💡 You don't *have* to use Portainer — `pideploy` deploys via `docker compose` regardless. But since Portainer manages the same Docker engine, your deployed apps appear there for free. Highly recommended for logs/restarts at a glance.

</details>

<details>
<summary><b>2. Tailscale</b> — private network + HTTPS</summary>

<br>

Install and join your tailnet:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Enable two things so `pideploy serve` can mint HTTPS certificates **without sudo**:

1. **Enable HTTPS / Serve** for your tailnet (one-time, in the admin console):
   <https://login.tailscale.com/admin/dns> → enable **MagicDNS** and **HTTPS Certificates**.
2. **Let your user drive Tailscale** without root:
   ```bash
   sudo tailscale set --operator="$USER"
   ```

Now `pideploy serve <port>` gives any app a `https://<host>.<tailnet>.ts.net` URL, reachable from every device on your tailnet — and nowhere else.

</details>

<details>
<summary><b>3. GitHub CLI</b> — auth + runner tokens</summary>

<br>

Install the GitHub CLI and log in with the scopes `pideploy` needs to register runners and push workflow files:

```bash
# install: https://github.com/cli/cli#installation
gh auth login                        # choose HTTPS; grant 'repo' + 'workflow' scopes
gh auth status                       # confirm: should list 'repo' and 'workflow'
```

> **Runner scope note.** On a **personal** GitHub account, a self-hosted runner is tied to a single repo — so `pideploy` registers **one runner per repo**. If you have many repos, consider a **free GitHub organization** with an org-level runner (a future `pideploy` mode). Everything works on a personal account today; it's just one runner service per repo.

</details>

<details>
<summary><b>4. Host prep</b> — keep runners alive across reboots</summary>

<br>

The runner runs as a **user** systemd service (no root). For user services to keep running after you log out or reboot, enable *lingering* once:

```bash
sudo loginctl enable-linger "$USER"
```

`pideploy doctor` and `pideploy status` both warn you if this isn't set.

</details>

---

## 🛠 Installation

```bash
git clone https://github.com/<you>/pideploy
cd pideploy
./install.sh          # symlinks ./pideploy -> ~/.local/bin/pideploy
```

Or manually:

```bash
install -Dm755 pideploy ~/.local/bin/pideploy
```

Make sure `~/.local/bin` is on your `PATH`. Then run `pideploy doctor`.

---

## ⚙️ How it works

```
 ┌────────────┐   git push    ┌──────────┐   self-hosted runner   ┌──────────────┐
 │ your dev   │ ────────────▶ │  GitHub  │ ─────(outbound)──────▶ │ Raspberry Pi │
 │ machine    │               │ Actions  │   builds + compose up  │  (this host) │
 └────────────┘               └──────────┘                        └──────┬───────┘
        ▲                                                                  │
        │   pideploy init / deploy / status / serve                       │ shares the
        │                                                                  │ Docker engine
        │                                                                  ▼
        │                                                          ┌──────────────┐
        └────── https://<host>.ts.net  ◀── tailscale serve ──────  │  Portainer   │
                  (tailnet-only, TLS)                               │  sees stacks │
                                                                    └──────────────┘
```

When you run `pideploy init`, it:

1. **Scaffolds** a `Dockerfile` (auto-detected for Node / Python / Go, or a static fallback), a `docker-compose.yml` (binds `127.0.0.1:<port>`, names the stack), and `.github/workflows/deploy.yml`.
2. **Writes `.pideploy.conf`** — your repo's deploy settings (port, name, branch). Safe to commit; contains no secrets.
3. **Registers a self-hosted runner** on the Pi as a user systemd service (`pideploy-runner@<owner-repo>`).
4. **Commits & pushes** — which triggers the first deploy.

Every subsequent push runs `docker compose up -d --build` on the Pi. Because the runner dials *out* to GitHub, **no inbound port or webhook is ever required** — which is exactly why this works on a tailnet-only Pi.

---

## 📖 Command reference

All data commands accept `--json`. Run `pideploy help <command>` for every option.

| Command | What it does |
|---------|--------------|
| `pideploy init [--port N] [--name NAME] [--serve]` | Set up the current repo to deploy on push |
| `pideploy deploy` | Trigger a deploy now (workflow_dispatch, else empty commit) |
| `pideploy status` | Runners, running stacks, Tailscale serve, linger |
| `pideploy serve <port>` / `unserve <port>` | Expose / stop exposing a port over Tailscale HTTPS |
| `pideploy logs [app]` | Tail a deployed app's logs |
| `pideploy config [list\|get\|set\|edit]` | Manage defaults |
| `pideploy rm` | Deregister this repo's runner |
| `pideploy setup` | One-time host prep (linger, Tailscale operator) |
| `pideploy doctor` | Check all prerequisites (exit 1 if any fail) |
| `pideploy agent` / `--agent` | Print the full operating manual for AI agents |
| `pideploy skill` / `--skill` | Print a ready-to-install Claude Code skill |
| `pideploy help [command]` | Overview, or detailed help for one command |
| `pideploy version` | Print version |

Global flags: `--json` (structured output) · `--agent` · `--skill` · `--yes` (no-op) · `--port N` · `--name NAME` · `--serve` / `--no-serve`

---

## 🎛 Configuration

Precedence (highest first): **CLI flags → per-repo `.pideploy.conf` → global config → built-in defaults.**

```bash
pideploy config list                 # show effective config
pideploy config set default_port 3000
pideploy config get node_version
pideploy config edit                 # open in $EDITOR
```

| Key | Default | Meaning |
|-----|---------|---------|
| `default_port` | `8080` | Port the app binds (localhost) |
| `default_branch` | `main` | Branch whose pushes deploy |
| `auto_serve` | `false` | Run `serve` automatically after `init` |
| `prune_images` | `true` | Prune dangling images after each deploy |
| `runner_label` | `pideploy` | Label applied to runners |
| `node_version` / `python_version` / `go_version` | `22` / `3.12` / `1.23` | Base image versions for scaffolded Dockerfiles |
| `app_name` | _(repo name)_ | Per-repo: stack/container name (written to `.pideploy.conf`) |

Global config lives at `~/.config/pideploy/config`; per-repo overrides at `.pideploy.conf` in the repo root.

---

## 🔒 Security model

`pideploy` is built to be private by default — but a **self-hosted runner runs code from your repo on your hardware**, so understand these rules:

- **Apps bind to `127.0.0.1` only.** They're never on your LAN or the internet — only the Tailscale HTTPS proxy fronts them, tailnet-only.
- **No inbound exposure.** The runner connects out to GitHub; your Pi opens no ports. (GitHub webhooks *cannot* reach a tailnet-only host — `pideploy` deliberately doesn't use them.)
- **Public repos: never add a `pull_request` trigger.** That would let a stranger's fork run code on your Pi. The generated workflow triggers only on `push` to your branch and manual dispatch — and says so in a comment. Keep it that way.
- **Secrets never go in git.** `.pideploy.conf` holds only port/name/branch. `init` adds `.env` to `.gitignore`. Put real secrets in **GitHub Actions secrets** or **Portainer environment variables**.
- **Tailscale traffic is end-to-end encrypted** (WireGuard), so plain-HTTP-behind-serve is still private; `serve` adds a real TLS cert on top so browsers are happy too.

| File | Commit it? | Why |
|------|:---:|------|
| `.pideploy.conf` | ✅ | port/name/branch — reproducible, no secrets |
| `Dockerfile`, `docker-compose.yml`, `deploy.yml` | ✅ | infra-as-code |
| `.env` / API keys / certs | ❌ | gitignored — use Actions/Portainer secrets |

---

## 🤖 AI-ready

Three layers so any agent can drive `pideploy` reliably:

```bash
pideploy --agent                                   # full operating manual (architecture, lifecycle, quickstart)
pideploy --skill > .claude/skills/pideploy/SKILL.md  # install a Claude Code skill (directives, rules, troubleshooting)
pideploy help <command>                            # detailed help + every option for one command
```

Plus the machine-friendly contract every command honors: **data on stdout, diagnostics on stderr, exit codes `0/1/2`, and `--json`** for structured output. Tell an agent *"use `pideploy --agent`"* (or install the skill) and it can set up and operate deployments autonomously.

---

## 🧪 Development & tests

The test suite is **hermetic** — it mocks `gh`, `docker`, `tailscale`, `systemctl`, and `loginctl`, so it never touches real services and needs no network.

```bash
tests/run.sh            # run all checks
tests/run.sh -v         # verbose (show every passing assertion)
```

Covers pure functions, the config precedence chain, every command's surface, the agent manual, and a full mocked `init → status → serve → deploy → rm` integration flow.

---

## 🧯 Troubleshooting

| Symptom | Fix |
|---------|-----|
| Runner shows `● inactive` in `status` | `systemctl --user status pideploy-runner@<owner-repo>`; ensure `loginctl enable-linger $USER` is set |
| Runners die after reboot/logout | Enable lingering: `sudo loginctl enable-linger $USER` |
| `serve` says "access denied" | Run once: `sudo tailscale set --operator=$USER` |
| No HTTPS cert / serve fails | Enable **HTTPS Certificates** in the Tailscale admin console |
| Deploy ran but app unreachable | Confirm the app listens on `<port>` inside the container and compose maps `127.0.0.1:<port>:<port>`, then `pideploy serve <port>` |
| `init` fails: no GitHub remote | `gh repo create --source=. --private --push` first |
| Deploys don't trigger | Check `gh auth status` has `repo` + `workflow` scopes |

Still stuck? `pideploy doctor` pinpoints the broken prerequisite.

---

## 📋 Roadmap

See [`PLAN.md`](PLAN.md) for the full plan. Highlights:

- Path-based multi-app serve (multiple apps under one host)
- `pideploy setup` — one-command host bootstrap
- Org-level runner mode (one runner, many repos)
- Optional Portainer-API Git-stack integration
- CI (tests + shellcheck) on GitHub

---

## 📜 License

MIT — see [`LICENSE`](LICENSE).

<div align="center">
<sub>Built for people who'd rather own their deploys. <code>git push</code> and forget.</sub>
</div>
