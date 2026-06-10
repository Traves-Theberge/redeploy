# Start Here 🚀

**redeploy** turns any git repo into push-to-deploy on a machine you own: every
`git push` builds your app with Docker on your **host** (a Raspberry Pi or any
Linux box) and runs it — privately, reachable over Tailscale HTTPS, visible in
Portainer. No cloud, no open ports.

```
  your laptop  ── git push ──▶  GitHub  ── runs the job on ──▶  your host (the Pi)
                                                                  builds + runs your app
                                                                  → Tailscale HTTPS URL
```

> **The one rule:** the deploy always runs **on the host** (where the runner lives),
> never on the machine you typed the command from.

---

## 0. What you'll need

- A **Linux host** with internet (a Raspberry Pi is perfect) — this is where apps run.
- A **GitHub account**.
- (recommended) A free **Tailscale** account — for private HTTPS access to your apps.
- A repo that **listens on `$PORT`** (redeploy sets it) and lives on GitHub.

You set up the host **once**. After that you just `git push`. Run `redeploy doctor`
at any point — it checks every prerequisite below and tells you exactly what's missing.

---

## 1. Set up the host — one prerequisite at a time

Do these **on the host** (sit at the Pi, or SSH in). Each step has an install and a
verify so you know it worked.

### 1a. Docker — runs your containers
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"          # lets you run docker without sudo
#   ↑ log out and back in (or reboot) for the group to take effect
docker run --rm hello-world              # verify: prints "Hello from Docker!"
```

### 1b. GitHub CLI (`gh`) — auth + runner enrollment
redeploy uses `gh` to register the runner and push workflows, so it must be logged in
with the right scopes.
```bash
# install: https://github.com/cli/cli#installation   (apt: sudo apt install gh)
gh auth login                            # choose HTTPS; grant 'repo' + 'workflow' scopes
gh auth status                           # verify: shows your account + 'repo','workflow'
```

### 1c. Tailscale — private HTTPS access to your apps
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up                        # log into your tailnet
sudo tailscale set --operator="$USER"    # so `redeploy serve` needs no sudo
tailscale status                         # verify: lists this machine with an IP
```
Then in the Tailscale admin console (one-time): **enable MagicDNS and HTTPS
Certificates** at <https://login.tailscale.com/admin/dns>. (Apps get
`https://<host>.<tailnet>.ts.net/...` URLs.)

### 1d. redeploy
```bash
curl -fsSL https://raw.githubusercontent.com/Traves-Theberge/redeploy/main/install.sh | bash
redeploy version                         # verify: redeploy 1.1.0
#   if it says ~/.local/bin isn't on PATH, add it:
#   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

### 1e. Finish host prep
```bash
redeploy setup        # enables systemd 'linger' (runners survive reboot) + tailscale operator
#   if it prints a sudo command for linger, run it once:  sudo loginctl enable-linger $USER
redeploy doctor       # verify: every line is 'ok' (tailscale-up/linger may be WARN — fine)
```

### 1f. (Optional) Portainer — a web dashboard for your containers
```bash
mkdir -p ~/apps/portainer/data
docker run -d --name portainer --restart unless-stopped -p 127.0.0.1:9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro -v ~/apps/portainer/data:/data \
  portainer/portainer-ce:latest
redeploy serve 9000   # expose it over Tailscale → opens at the printed https URL
```

That's the whole host setup. You never repeat it.

---

## 2. Add a repo — pick the style that fits you

### A) On the host
SSH into the host (or sit at it) and run, inside a repo with a GitHub remote:
```bash
redeploy init          # auto-picks a free port, scaffolds, registers the runner, pushes
# or, for a repo that's on GitHub but not cloned here:
redeploy onboard <owner>/<repo>
```

### B) From your laptop (remote mode) — recommended day-to-day
Configure your laptop once, then onboard repos without leaving it. Needs Tailscale
SSH to the host (`sudo tailscale set --ssh` on the host).

```bash
# on your laptop, once:
curl -fsSL https://raw.githubusercontent.com/Traves-Theberge/redeploy/main/install.sh | bash
gh auth status                                  # logged in? (repo + workflow)
ssh you@<host> 'redeploy version'               # confirm Tailscale SSH reaches the host
redeploy config set runner_host you@<host>      # turn on remote mode

# then, per repo:
cd ~/code/my-app
redeploy init          # SSHes to the host, registers the runner THERE, scaffolds + pushes
```
> In remote mode your laptop needs **no Docker** — `init` only scaffolds + pushes,
> and registers the runner on the host over SSH.

---

## 3. Every day (from anywhere)

```bash
git push               # rebuilds + redeploys on the host, automatically
redeploy status        # is the runner active? is the container up?
redeploy serve         # expose it over Tailscale → prints the https URL
redeploy url           # "where's my app?" → the endpoint
redeploy logs          # tail its logs
```

Deploy **many apps** to one host — each gets a distinct, stable port (no collisions)
and a distinct Tailscale path (`https://<host>/<app>`), so they all coexist.

---

## Handy

```bash
redeploy ports         # which repo uses which port
redeploy doctor        # fix any prerequisite
redeploy rm            # remove a repo's runner (frees its port)
redeploy help <cmd>    # detailed help for any command
redeploy --agent       # the full operating manual (AI-agent friendly)
redeploy --skill > .claude/skills/redeploy/SKILL.md   # install a Claude Code skill
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `doctor` shows a `FAIL` | do what it says (install the dep, `gh auth login`, etc.) |
| `linger` is `WARN` | `sudo loginctl enable-linger $USER` (so runners survive reboot) |
| remote `init`: ssh fails | confirm `ssh you@<host> 'redeploy version'` works first |
| remote `init`: "redeploy not found" over ssh | add `~/.local/bin` to the host's `~/.bashrc` PATH |
| `serve` "access denied" | `sudo tailscale set --operator=$USER` |
| app unreachable after deploy | make sure it listens on `$PORT`; then `redeploy serve` |

Full docs: [README.md](README.md) · version history: [CHANGELOG.md](CHANGELOG.md) ·
agents: [AGENTS.md](AGENTS.md).
