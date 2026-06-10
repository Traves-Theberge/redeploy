<div align="center">

<img src="assets/redeploy-logo.png" alt="redeploy" width="200">

# redeploy

**Turn any git repo into a push-to-deploy app on a Linux host you own.**

`git push` → builds with Docker on your host → shows up in Portainer → reachable anywhere over Tailscale.

**👉 New here? Read [START-HERE.md](START-HERE.md)** — a step-by-step setup for the whole thing.

[Quick start](#-60-second-quick-start) · [Setup](#-prerequisites--setup) · [How it works](#-how-it-works) · [Commands](#-command-reference) · [Security](#-security-model) · [AI-ready](#-ai-ready)

![ci](https://github.com/Traves-Theberge/redeploy/actions/workflows/ci.yml/badge.svg)
![release](https://img.shields.io/github/v/release/Traves-Theberge/redeploy?sort=semver)
![shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![tests](https://img.shields.io/badge/tests-236%20hermetic-32CD32)
![license](https://img.shields.io/badge/license-MIT-blue)
![self-hosted](https://img.shields.io/badge/self--hosted-Linux%20%C2%B7%20Docker-2496ED?logo=docker&logoColor=white)

</div>

---

## What is this?

`redeploy` is a single, dependency-light CLI that gives you **your own Heroku/Vercel on hardware you own**. You run one command inside a repo, and from then on every `git push` builds your app and deploys it — privately, over your Tailscale network, visible and manageable in Portainer.

No cloud bill. No exposing ports to the internet. No webhooks poking holes in your network. Just `git push`.

Deploy **many apps to one host** with no port collisions, expose them at distinct Tailscale URLs, and onboard new repos either on the host or **from your laptop over SSH** ([remote mode](#onboard-from-your-laptop-remote-mode)).

The CLI is **plain, non-interactive, and scriptable** — data on stdout, progress on stderr, stable exit codes, and `--json` on every data command. Great for you in a terminal and great for AI agents.

```console
$ cd my-app
$ redeploy init --port 8080
redeploy: repo=you/my-app app=my-app port=8080 branch=main runner=rd-you-my-app   # stderr
redeploy: wrote Dockerfile
redeploy: runner rd-you-my-app installed and started
redeploy: pushed (first deploy starting)
repo=you/my-app                                                                    # stdout
app=my-app
port=8080
runner=rd-you-my-app
runner_registered=true
pushed=true

$ redeploy serve 8080
https://your-pi.your-tailnet.ts.net/        # the URL is the only thing on stdout

$ redeploy status --json
{"runners":[{"name":"you-my-app","active":true}],"stacks":[{"name":"my-app","status":"Up","ports":"127.0.0.1:8080->8080/tcp"}],"serve":["https://your-pi.your-tailnet.ts.net/"],"linger":true}
```

That's the whole workflow. Edit code, `git push`, done.

---

## ✨ Why it's different

- **Push-to-deploy, fully private.** The deploy path is GitHub Actions → a self-hosted runner on *your* host. Your host never needs an inbound port; the runner dials out.
- **Works behind Tailscale.** Because nothing inbound is required, your host can live entirely on your tailnet. Apps get real HTTPS via `tailscale serve`.
- **Portainer-native.** The runner and Portainer share one Docker engine, so every deployed app shows up in Portainer automatically — logs, restarts, the works.
- **Plain & scriptable.** No colors, boxes, or prompts. Data → stdout, diagnostics → stderr, exit codes `0/1/2`, and `--json` on every data command.
- **Configurable.** Global defaults + per-repo `.redeploy.conf`, overridable by flags.
- **AI-ready, three ways.** `redeploy --agent` prints a full operating manual; `redeploy --skill` emits a ready-to-install Claude Code skill; `redeploy help <command>` documents every option.

---

## 🚀 60-second quick start

> Assumes the [prerequisites](#-prerequisites--setup) below are done (Tailscale, Portainer, GitHub, host prep). First time? Do those once, then this is all you ever run.

```bash
# 1. install
git clone https://github.com/Traves-Theberge/redeploy && cd redeploy
./install.sh                       # symlinks `redeploy` into ~/.local/bin

# 2. verify your machine is ready
redeploy doctor

# 3. in any repo with a GitHub remote:
cd ~/code/my-app
redeploy init                      # scaffold + runner + first deploy
redeploy serve 8080                # expose it over Tailscale HTTPS
```

From then on: **`git push` deploys.** To redeploy without code changes, `redeploy deploy`.

---

## 📦 Prerequisites & setup

`redeploy` orchestrates four things on **one Linux host** (designed for a Raspberry Pi, works on any Linux box): **Docker + Portainer**, **Tailscale**, **GitHub (`gh`)**, and a **user systemd** service for the runner. Set each up once.

Run `redeploy doctor` at any point — it checks every prerequisite and tells you exactly what's missing.

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

> 💡 You don't *have* to use Portainer — `redeploy` deploys via `docker compose` regardless. But since Portainer manages the same Docker engine, your deployed apps appear there for free. Highly recommended for logs/restarts at a glance.

</details>

<details>
<summary><b>2. Tailscale</b> — private network + HTTPS</summary>

<br>

Install and join your tailnet:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Enable two things so `redeploy serve` can mint HTTPS certificates **without sudo**:

1. **Enable HTTPS / Serve** for your tailnet (one-time, in the admin console):
   <https://login.tailscale.com/admin/dns> → enable **MagicDNS** and **HTTPS Certificates**.
2. **Let your user drive Tailscale** without root:
   ```bash
   sudo tailscale set --operator="$USER"
   ```

Now `redeploy serve <port>` gives any app a `https://<host>.<tailnet>.ts.net` URL, reachable from every device on your tailnet — and nowhere else.

</details>

<details>
<summary><b>3. GitHub CLI</b> — auth + runner tokens</summary>

<br>

Install the GitHub CLI and log in with the scopes `redeploy` needs to register runners and push workflow files:

```bash
# install: https://github.com/cli/cli#installation
gh auth login                        # choose HTTPS; grant 'repo' + 'workflow' scopes
gh auth status                       # confirm: should list 'repo' and 'workflow'
```

Also set a **real git identity** — `redeploy` commits on your behalf during `init`/`deploy`, and it **refuses to commit** with an unset or generic identity (e.g. `noreply@users.noreply.github.com`), which GitHub mis-attributes to whatever account claimed that address:

```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"   # a real address you control
```

> `redeploy doctor` reports this as the `git-identity` check.

> **Runner scope note.** On a **personal** GitHub account, a self-hosted runner is tied to a single repo — so `redeploy` registers **one runner per repo**. If you have many repos, consider a **free GitHub organization** with an org-level runner (a future `redeploy` mode). Everything works on a personal account today; it's just one runner service per repo.

</details>

<details>
<summary><b>4. Host prep</b> — keep runners alive across reboots</summary>

<br>

The runner runs as a **user** systemd service (no root). For user services to keep running after you log out or reboot, enable *lingering* once:

```bash
sudo loginctl enable-linger "$USER"
```

`redeploy doctor` and `redeploy status` both warn you if this isn't set.

</details>

---

## 🛠 Installation

`redeploy` is a **single, self-contained Bash script** (no runtime, no package manager). It installs on the **Linux deploy host** — the machine that runs your apps (a Raspberry Pi or any Linux box with Docker + systemd).

### Where does it go? (platform)

| Your machine | Install redeploy? |
|---|---|
| **Linux deploy host** (Pi / server) | **Yes** — this is where it runs |
| **macOS / Windows / Linux dev laptop** | **No** — you just `git push`; the host does the rest |

> The deploy host **must be Linux** (the self-hosted runner uses systemd user services + linger). On Windows, run the host inside **WSL2**. macOS can run the CLI but can't be a *host*.

### Install (on the Linux host)

**One-liner (recommended)** — installs the latest [release](https://github.com/Traves-Theberge/redeploy/releases):

```bash
curl -fsSL https://raw.githubusercontent.com/Traves-Theberge/redeploy/main/install.sh | bash
```

**Pin a specific version** (or just grab the script):

```bash
curl -fsSL https://github.com/Traves-Theberge/redeploy/releases/latest/download/redeploy -o ~/.local/bin/redeploy
chmod +x ~/.local/bin/redeploy
```

**From a clone** (gets tests + docs):

```bash
git clone https://github.com/Traves-Theberge/redeploy && cd redeploy && ./install.sh
```

Ensure `~/.local/bin` is on your `PATH` (the installer warns if not), then:

```bash
redeploy version
redeploy setup        # one-time host prep (linger + tailscale operator)
redeploy doctor       # confirm every prerequisite is ok
```

> `redeploy` orchestrates Docker, Tailscale, and the GitHub CLI — see [Prerequisites & setup](#-prerequisites--setup). `redeploy doctor` tells you exactly what's missing.

**Update:** re-run the one-liner. **Uninstall:** `rm ~/.local/bin/redeploy` (and `redeploy rm` in any repo whose runner you want removed). See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## ⚙️ How it works

```
 ┌────────────┐   git push    ┌──────────┐   self-hosted runner   ┌──────────────┐
 │ your dev   │ ────────────▶ │  GitHub  │ ─────(outbound)──────▶ │  Linux host  │
 │ machine    │               │ Actions  │   builds + compose up  │  (Pi/VPS/…)  │
 └────────────┘               └──────────┘                        └──────┬───────┘
        ▲                                                                  │
        │   redeploy init / deploy / status / serve                       │ shares the
        │                                                                  │ Docker engine
        │                                                                  ▼
        │                                                          ┌──────────────┐
        └────── https://<host>.ts.net  ◀── tailscale serve ──────  │  Portainer   │
                  (tailnet-only, TLS)                               │  sees stacks │
                                                                    └──────────────┘
```

When you run `redeploy init`, it:

1. **Scaffolds** a `Dockerfile` (auto-detected for Node / Python / Go, or a static fallback), a `docker-compose.yml` (binds `127.0.0.1:<port>`, names the stack), and `.github/workflows/deploy.yml`.
2. **Writes `.redeploy.conf`** — your repo's deploy settings (port, name, branch). Safe to commit; contains no secrets.
3. **Registers a self-hosted runner** on the host as a user systemd service (`redeploy-runner@<owner-repo>`).
4. **Commits & pushes** — which triggers the first deploy.

### How it knows *where* to deploy (no IP, no SSH, no target config)

There is **no address, hostname, SSH key, or deploy target anywhere** in your repo. Routing is done entirely by **GitHub's self-hosted runner + label matching**:

- `init` registers a runner **process on this host** with GitHub, tagged with labels like `[self-hosted, Linux, ARM64, redeploy]`. It holds an **outbound** long-poll connection to GitHub ("I'm online; here are my labels").
- The generated workflow says `runs-on: [self-hosted, redeploy]` — that's **not an address, it's a label requirement**.
- When a job is queued, GitHub hands it to a runner whose labels match. The only one that matches for your repo is *yours, on this host* — so the job runs here.

The host reaches **out** to GitHub; GitHub never reaches **in**. That's why it needs zero open ports and works on a tailnet-only machine. Move the runner to a different machine and the same `git push` deploys there instead — **the repo never changes**.

### What every push does, end to end

```
git push (to your branch)
   └─ GitHub: on.push matches → queues the "deploy" job (runs-on: [self-hosted, <label>])
        └─ your runner claims it and runs these steps ON THIS HOST:
             1. actions/checkout@v4              clone the repo into the runner workdir
             2. Provision .env from secret       printf "$DOTENV" > .env   (secrets.<NAME>, masked)
             3. docker compose up -d --build      build images + (re)start containers
             4. docker image prune -f             drop dangling layers
             5. Remove provisioned .env           wipe the secret file (if: always())
   → containers run on this host's Docker engine → Portainer sees them
   → redeploy serve <port> exposes one over Tailscale HTTPS
```

Because the runner dials *out*, **no inbound port or webhook is ever required** — exactly why this works on a tailnet-only host.

---

## 📖 Command reference

All data commands accept `--json`. Run `redeploy help <command>` for every option.

| Command | What it does |
|---------|--------------|
| `redeploy init [--port N] [--name NAME] [--serve]` | Set up the current repo to deploy on push |
| `redeploy onboard <owner/repo>` | Clone a repo onto this host + init it (one step) |
| `redeploy config template` | Print a shareable placeholder host config |
| `redeploy deploy` | Trigger a deploy now (workflow_dispatch, else empty commit) |
| `redeploy status` | Runners, running stacks, Tailscale serve, linger |
| `redeploy serve [port] [--path /name] [--port-mode]` / `unserve …` | Expose / stop exposing over Tailscale HTTPS (path-based; many apps coexist) |
| `redeploy url` / `open` | Print (or open) this repo's app endpoint URL |
| `redeploy logs [app]` | Tail a deployed app's logs |
| `redeploy config [list\|get\|set\|edit]` | Manage defaults |
| `redeploy ports` | List which repo uses which port (host registry) |
| `redeploy env [--name NAME]` | Sync local `.env` → a GitHub Actions secret |
| `redeploy rm` | Deregister this repo's runner |
| `redeploy setup` | One-time host prep (linger, Tailscale operator) |
| `redeploy doctor` | Check all prerequisites (exit 1 if any fail) |
| `redeploy update [--check]` | Upgrade `redeploy` to the latest release (`--check`: just compare versions) |
| `redeploy agent` / `--agent` | Print the full operating manual for AI agents |
| `redeploy skill` / `--skill` | Print a ready-to-install Claude Code skill |
| `redeploy help [command]` | Overview, or detailed help for one command |
| `redeploy version` | Print version |

Global flags: `--json` (structured output) · `--agent` · `--skill` · `--yes` (no-op) · `--port N` · `--name NAME` · `--serve` / `--no-serve` · `--dotenv-secret NAME` / `--no-dotenv`

---

## 🔑 Secrets — `.env` as the source of truth

Apps usually need secrets (API keys, tokens). Because the runner builds in a **fresh checkout** that has no gitignored files, your local `.env` won't be there — so `redeploy` bridges it for you, the secure way:

```
   .env (local, gitignored)         <-- you edit this; the source of truth
        │  redeploy init  (or: redeploy env)
        ▼
   GitHub Actions secret            <-- gh secret set  (encrypted)
        │  deploy workflow
        ▼
   .env recreated on the runner     <-- before `docker compose up`
```

- When a `.env` exists, `init` uploads it to a GitHub Actions secret (default name `REDEPLOY_DOTENV`) via `gh secret set`, and the generated workflow recreates `.env` on the runner before `docker compose up`.
- Edit `.env` and run **`redeploy env`** to re-sync. Use `--dotenv-secret NAME` to choose the secret name, or `--no-dotenv` to skip.
- `.env` is **never committed** (init gitignores it). Secrets live only in your local file and GitHub's encrypted secret store.

---

## 🎛 Configuration — one host config, many repos

`redeploy` has a **host config** at `~/.config/redeploy/config` that describes *this machine as a deploy target* — and it's **reused by every repo you onboard here.** It lives outside any repo, so it never leaks. Generate a shareable placeholder (the only host-config artifact that's safe to commit) and fill it in:

```bash
redeploy config template > ~/.config/redeploy/config   # placeholders → your config
redeploy config edit                                   # fill in your values
redeploy config list                                   # show effective config
redeploy config set default_port 3000                  # change a default
```

Precedence (highest first): **CLI flags → per-repo `.redeploy.conf` → host config → built-in defaults.**

| Key | Scope | Default | Meaning |
|-----|-------|---------|---------|
| `deploy_host` | host | _(hostname)_ | Friendly name for this target (shown in `status`) |
| `portainer_url` | host | — | Portainer URL on this host (reference/links) |
| `runner_label` | host | `redeploy` | Label that routes Actions jobs to this host's runner |
| `default_port` | host | `8080` | Port the app binds (localhost) |
| `default_branch` | host | `main` | Branch whose pushes deploy |
| `auto_serve` | host | `false` | Run `serve` automatically after `init` |
| `prune_images` | host | `true` | Prune dangling images after each deploy |
| `node_version` / `python_version` / `go_version` | host | `22` / `3.12` / `1.23` | Base image versions for scaffolded Dockerfiles |
| `app_name` | repo | _(repo name)_ | Stack/container name (in `.redeploy.conf`) |
| `dotenv_secret` | repo | `REDEPLOY_DOTENV` | GitHub secret name `.env` is synced to (in `.redeploy.conf`) |

**Onboard any repo to this host in one step:** `redeploy onboard <owner/repo> --port N` (run on the host — clones the repo and inits it, so it deploys here).

### Onboard from your laptop (remote mode)

The runner lives on the host, so enrolling a repo's runner has to *touch* the host once. **Remote mode** automates that over SSH so you never leave your laptop:

```bash
# on your laptop, once: install redeploy + point it at the host
redeploy config set runner_host you@your-pi      # any SSH target (Tailscale SSH works great)

# then, per repo, from the laptop:
cd ~/code/my-app
redeploy init        # SSHes to the host, registers the runner there, scaffolds + pushes
git push             # → deploys to the host, forever
```

In remote mode, `init` runs `redeploy register <repo>` on the host (which assigns the port and returns the label), then only scaffolds and pushes locally — so **no Docker or systemd is needed on your laptop**. The host just needs redeploy installed and SSH reachable (`sudo tailscale set --ssh` enables Tailscale SSH). On a personal GitHub account a runner is still one-per-repo; remote mode just does that host-side enrollment for you over SSH. (A GitHub **org** would let a single runner serve every repo — see the org-runner item in [PLAN.md](PLAN.md).)

### Many apps, no port collisions

Deploy as many repos to one host as you like — `redeploy` keeps every app on a **distinct, stable port** via a host registry (`~/.redeploy/ports`):

- Omit `--port` and `init` **auto-assigns** the lowest free port at/above `default_port` (8080). First app → 8080, next → 8081, and so on.
- Pass an explicit `--port` that another app already uses and it **fails fast** (exit 1) with a suggested free port.
- Re-deploying a repo **reuses** its recorded port; `redeploy rm` frees it. See all assignments with **`redeploy ports`**.

```console
$ redeploy ports
you/api=8080
you/web=8081
you/bot=8082
```

### Exposing many apps over Tailscale (path-based)

`redeploy serve` is **path-based** by default: each app mounts at a distinct path on your one tailnet HTTPS host, so they all stay reachable at once.

```console
$ cd ~/code/api && redeploy serve      # in a repo: port + path inferred
https://your-pi.ts.net/api
$ cd ~/code/web && redeploy serve
https://your-pi.ts.net/web
$ cd ~/code/bot && redeploy serve
https://your-pi.ts.net/bot
```

- In a repo, `serve` needs no args — the **port** comes from `.redeploy.conf` and the **path** defaults to `/<app_name>`. Override with `--path /custom`.
- **Caveat:** the app must tolerate a sub-path (relative links, or a configurable base URL). If it can't, use **`--port-mode`** to give it the root of its own HTTPS port: `redeploy serve 8080 --port-mode` → `https://your-pi.ts.net:8080/`.
- `redeploy unserve` (same flags) removes just that one app's route; the others stay up.

**Forgot an app's URL?** Run **`redeploy url`** inside its repo — it prints the live endpoint (the served `https://…` URL if exposed, otherwise the local `http://127.0.0.1:<port>/` with a reminder to `serve`). `redeploy open` launches it in a browser.

> Tailscale is only the **access** layer here — it never affects *where* a deploy runs (that's the runner label).

### Open-source / leak safety
- The **real host config never lives in a repo** — only `config.example` (placeholders) is committed.
- `.redeploy.conf` is committed but **secret-free** (only the secret's *name*).
- `.env` and any real config are gitignored; secrets reach the runner only via GitHub's **encrypted** secret store.

---

## 🔒 Security model

`redeploy` is built to be private by default — but a **self-hosted runner runs code from your repo on your hardware**, so understand these rules:

- **Apps bind to `127.0.0.1` only.** They're never on your LAN or the internet — only the Tailscale HTTPS proxy fronts them, tailnet-only.
- **No inbound exposure.** The runner connects out to GitHub; your host opens no ports. (GitHub webhooks *cannot* reach a tailnet-only host — `redeploy` deliberately doesn't use them.)
- **Public repos: never add a `pull_request` trigger.** That would let a stranger's fork run code on your host. The generated workflow triggers only on `push` to your branch and manual dispatch — and says so in a comment. Keep it that way.
- **Secrets never go in git.** `.redeploy.conf` holds only port/name/branch. `init` adds `.env` to `.gitignore`. Put real secrets in **GitHub Actions secrets** or **Portainer environment variables**.
- **Tailscale traffic is end-to-end encrypted** (WireGuard), so plain-HTTP-behind-serve is still private; `serve` adds a real TLS cert on top so browsers are happy too.

| File | Commit it? | Why |
|------|:---:|------|
| `.redeploy.conf` | ✅ | port/name/branch — reproducible, no secrets |
| `Dockerfile`, `docker-compose.yml`, `deploy.yml` | ✅ | infra-as-code |
| `.env` / API keys / certs | ❌ | gitignored — use Actions/Portainer secrets |

---

## 🤖 AI-ready

Three layers so any agent can drive `redeploy` reliably:

```bash
redeploy --agent                                   # full operating manual (architecture, lifecycle, quickstart)
redeploy --skill > .claude/skills/redeploy/SKILL.md  # install a Claude Code skill (directives, rules, troubleshooting)
redeploy help <command>                            # detailed help + every option for one command
```

Plus the machine-friendly contract every command honors: **data on stdout, diagnostics on stderr, exit codes `0/1/2`, and `--json`** for structured output. Tell an agent *"use `redeploy --agent`"* (or install the skill) and it can set up and operate deployments autonomously.

---

## 🧪 Development & tests

The test suite is **hermetic** — it mocks `gh`, `docker`, `tailscale`, `systemctl`, and `loginctl`, so it never touches real services and needs no network. It runs in **CI** (`.github/workflows/ci.yml`) on every push/PR, alongside `shellcheck`.

```bash
tests/run.sh            # run all 154 checks
tests/run.sh -v         # verbose (show every passing assertion)
```

Covers pure functions, the config precedence chain (built-in → host → repo → flags), every command's surface, JSON shape/type and error-shape, secret leak-safety, generated-workflow YAML validity, and a full mocked `init → status → serve → deploy → rm` integration flow.

---

## 🧯 Troubleshooting

| Symptom | Fix |
|---------|-----|
| Runner shows `● inactive` in `status` | `systemctl --user status redeploy-runner@<owner-repo>`; ensure `loginctl enable-linger $USER` is set |
| Runners die after reboot/logout | Enable lingering: `sudo loginctl enable-linger $USER` |
| `serve` says "access denied" | Run once: `sudo tailscale set --operator=$USER` |
| No HTTPS cert / serve fails | Enable **HTTPS Certificates** in the Tailscale admin console |
| Deploy ran but app unreachable | Confirm the app listens on `<port>` inside the container and compose maps `127.0.0.1:<port>:<port>`, then `redeploy serve <port>` |
| `init` fails: no GitHub remote | `gh repo create --source=. --private --push` first |
| Deploys don't trigger | Check `gh auth status` has `repo` + `workflow` scopes |

Still stuck? `redeploy doctor` pinpoints the broken prerequisite.

---

## 📋 Roadmap

See [`PLAN.md`](PLAN.md) for the full plan. Highlights:

- ✅ Path-based multi-app serve (multiple apps under one host) — **done**
- `redeploy setup` — one-command host bootstrap
- Org-level runner mode (one runner, many repos)
- Optional Portainer-API Git-stack integration
- CI (tests + shellcheck) on GitHub

---

## 📜 License

MIT — see [`LICENSE`](LICENSE).

<div align="center">
<sub>Built for people who'd rather own their deploys. <code>git push</code> and forget.</sub>
</div>
