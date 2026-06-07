#!/usr/bin/env bash
# pideploy test suite — hermetic: mocks gh/docker/tailscale/systemctl/loginctl
# (in tests/mocks/), uses a throwaway $HOME/$PIDEPLOY_HOME sandbox, and touches
# no real services or network. Runs in CI (.github/workflows/ci.yml) + shellcheck.
#
# Usage: tests/run.sh            # run everything (exit 0 = all passed)
#        tests/run.sh -v         # verbose (show each passing assertion)
#
# Coverage map (one grp() per area):
#   Unit: pure functions ........ repo_slug, detect_dockerfile, tailnet_host, plain output
#   Unit: configuration ......... defaults + built-in→host→repo precedence, set/get/list
#   Host config & onboarding .... config template (leak-safe), config.example, path,
#                                  status target, onboard (clone+init)
#   CLI: surface ................ version, help, unknown-cmd error
#   CLI: agent manual ........... --agent content (architecture, routing, pipeline, json errors)
#   CLI: help & skill ........... usage sections, per-command help (every cmd), --skill
#   CLI: doctor & status ........ check output
#   Integration ................. init → status → serve → logs → deploy → rm (mocked, e2e)
#   Secrets: no leakage ......... .env→secret, value never printed/committed, workflow refs name
#   AI contract: JSON ........... valid JSON + strict shape/type for every data command
#   AI contract: streams/exit ... stdout=data, stderr=progress, exit codes 0/1/2
#   AI contract: error shape .... text vs json errors, empty stdout on error
#   Guards ...................... not-in-repo, unknown flag, missing-value usage errors
#
# Helpers: assert_eq/contains/absent/ok/fail/file/exit/json/struct (see below).
# lib() sources the CLI with PIDEPLOY_LIB=1 to unit-test internal functions.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/.." && pwd)/pideploy"
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1

PASS=0; FAIL=0
c_g=$'\033[32m'; c_r=$'\033[31m'; c_d=$'\033[2m'; c_b=$'\033[1m'; c_0=$'\033[0m'
ok()   { PASS=$((PASS+1)); [ "$VERBOSE" = 1 ] && printf '  %s✓%s %s\n' "$c_g" "$c_0" "$1"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n' "$c_r" "$c_0" "$1"; [ -n "${2:-}" ] && printf '      %s%s%s\n' "$c_d" "$2" "$c_0"; }
grp()  { printf '\n%s▸ %s%s\n' "$c_b" "$1" "$c_0"; }

assert_eq()       { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want='$3' got='$2'"; }
assert_contains() { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "missing '$3' in output";; esac; }
assert_absent()   { case "$2" in *"$3"*) bad "$1" "unexpected '$3'";; *) ok "$1";; esac; }
assert_ok()       { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "command failed: $2"; fi; }
assert_fail()     { if eval "$2" >/dev/null 2>&1; then bad "$1" "expected failure: $2"; else ok "$1"; fi; }
assert_file()     { [ -f "$2" ] && ok "$1" || bad "$1" "missing file: $2"; }
assert_exit()     { local r; eval "$2" >/dev/null 2>&1; r=$?; [ "$r" = "$3" ] && ok "$1" || bad "$1" "exit want=$3 got=$r"; }
assert_json()     { if command -v python3 >/dev/null 2>&1; then printf '%s' "$2" | python3 -m json.tool >/dev/null 2>&1 && ok "$1" || bad "$1" "invalid JSON: $2"; else ok "$1 (skip: no python3)"; fi; }
# assert_struct <name> <json> <python-bool-expr over `d`>  — strict shape/type check
assert_struct()   {
  if ! command -v python3 >/dev/null 2>&1; then ok "$1 (skip: no python3)"; return; fi
  if printf '%s' "$2" | python3 -c "import sys,json
d=json.load(sys.stdin)
assert ($3), 'shape check failed'" 2>/dev/null; then ok "$1"; else bad "$1" "bad shape/type: $2"; fi
}

# ── sandbox ──────────────────────────────────────────────────────────────────
SBOX="$(mktemp -d)"; trap 'rm -rf "$SBOX"' EXIT
export HOME="$SBOX/home"; mkdir -p "$HOME"
export XDG_CONFIG_HOME="$HOME/.config"
export PIDEPLOY_HOME="$SBOX/pd"; export PIDEPLOY_STATE="$SBOX/state"
export PATH="$HERE/mocks:$PATH"
export NO_COLOR=1
mkdir -p "$PIDEPLOY_HOME/runner-template"
# sandbox git identity (generic, no PII)
cat > "$HOME/.gitconfig" <<'G'
[user]
  name = Test User
  email = test@example.com
[init]
  defaultBranch = main
G
# fake runner template so init never downloads
cat > "$PIDEPLOY_HOME/runner-template/config.sh" <<'C'
#!/usr/bin/env bash
[ "$1" = remove ] && exit 0
exit 0
C
printf '#!/usr/bin/env bash\nsleep 0.1\n' > "$PIDEPLOY_HOME/runner-template/run.sh"
chmod +x "$PIDEPLOY_HOME/runner-template/config.sh" "$PIDEPLOY_HOME/runner-template/run.sh"
# Run from inside the (non-git) sandbox so the CWD's .pideploy.conf / git repo
# can never leak into load_config — tests are independent of where they're launched.
cd "$SBOX"

# call a library function in isolation
lib() { PIDEPLOY_LIB=1 bash -c "source $BIN; $1" 2>&1; }

# ════════════════════════════════════════════════════════════════════════════
grp "Unit: pure functions"
assert_eq "repo_slug lowercases & sanitizes" "$(lib 'repo_slug "Foo/Bar_Baz.QUX"')" "foo-bar-baz-qux"
assert_eq "repo_slug owner/repo"             "$(lib 'repo_slug "testuser/testrepo"')" "testuser-testrepo"

# detect_dockerfile per stack
nd="$SBOX/fx-node"; mkdir -p "$nd"; echo '{}' > "$nd/package.json"
assert_contains "detect node"   "$(lib "cd '$nd' && detect_dockerfile")" "FROM node:"
pd="$SBOX/fx-py"; mkdir -p "$pd"; touch "$pd/requirements.txt"
assert_contains "detect python" "$(lib "cd '$pd' && detect_dockerfile")" "FROM python:"
gd="$SBOX/fx-go"; mkdir -p "$gd"; touch "$gd/go.mod"
assert_contains "detect go"     "$(lib "cd '$gd' && detect_dockerfile")" "FROM golang:"
sd="$SBOX/fx-static"; mkdir -p "$sd"
assert_contains "detect static fallback" "$(lib "cd '$sd' && detect_dockerfile")" "FROM nginx:"

# tailnet_host parses DNSName from (mocked) tailscale
assert_eq "tailnet_host strips trailing dot" "$(lib 'tailnet_host')" "test-pi.tailnet.ts.net"

# output is plain: no ANSI escape sequences anywhere
esc=$'\033'
assert_absent "help has no ANSI"   "$($BIN help)"        "$esc"
assert_absent "status has no ANSI" "$($BIN status 2>&1)" "$esc"

# ════════════════════════════════════════════════════════════════════════════
grp "Unit: configuration"
# defaults present
assert_eq "default_port default" "$(lib 'echo "${CFG[default_port]}"')" "8080"
# global config overrides built-in
mkdir -p "$XDG_CONFIG_HOME/pideploy"
echo "default_port=9999" > "$XDG_CONFIG_HOME/pideploy/config"
assert_eq "global config overrides default" "$(lib 'load_config; cfg default_port')" "9999"
# per-repo overrides global
rc="$SBOX/fx-repo"; mkdir -p "$rc"; ( cd "$rc" && git init -q )
echo "default_port=7777" > "$rc/.pideploy.conf"
assert_eq "repo conf overrides global" "$(lib "cd '$rc' && load_config; cfg default_port")" "7777"
# config set persists & get reads back
assert_ok  "config set"  "$BIN config set node_version 20"
assert_eq  "config get"  "$($BIN config get node_version)" "20"
assert_contains "config list shows key" "$($BIN config list)" "node_version"
rm -f "$XDG_CONFIG_HOME/pideploy/config"   # reset for later tests

# ════════════════════════════════════════════════════════════════════════════
grp "Host config & onboarding"
# config template — shareable placeholder, leak-safe (env values blank)
TPL="$($BIN config template)"
assert_contains "template: has runner_label"   "$TPL" "runner_label=pideploy"
assert_contains "template: documents deploy_host" "$TPL" "deploy_host="
assert_eq "template: deploy_host is blank (no real value)"  "$(printf '%s' "$TPL" | grep '^deploy_host=')"  "deploy_host="
assert_eq "template: portainer_url is blank (no real value)" "$(printf '%s' "$TPL" | grep '^portainer_url=')" "portainer_url="
# committed config.example must equal the generated template (and be leak-free)
assert_eq "config.example matches template" "$(cat "$(dirname "$BIN")/config.example")" "$TPL"
# config list/path expose host keys
assert_contains "config list has deploy_host"  "$($BIN config list)" "deploy_host"
assert_contains "config list has portainer_url" "$($BIN config list)" "portainer_url"
assert_contains "config path points at host config" "$($BIN config path)" "pideploy/config"
# status surfaces the deploy target
assert_contains "status shows target host" "$($BIN status 2>&1)" "target"
assert_struct   "status --json has host keys" "$($BIN status --json 2>/dev/null)" \
  "'deploy_host' in d and 'portainer_url' in d"
# onboard: usage + clone+init in one step
assert_exit "onboard without arg → 2" "$BIN onboard" 2
( git init -q --bare "$SBOX/onb.git"
  OS="$SBOX/onb-src"; mkdir -p "$OS"; cd "$OS"; git init -q; git remote add origin "$SBOX/onb.git"
  echo '{"name":"o","scripts":{"start":"true"}}' > package.json; git add -A; git commit -qm init; git branch -M main; git push -q -u origin main ) 2>/dev/null
PIDEPLOY_REPOS="$SBOX/onboarded" $BIN onboard "file://$SBOX/onb.git" --port 8080 --no-dotenv >/dev/null 2>&1
assert_ok   "onboard: cloned the repo onto the host" "[ -d '$SBOX/onboarded/onb/.git' ]"
assert_file "onboard: ran init (scaffolded Dockerfile)" "$SBOX/onboarded/onb/Dockerfile"

grp "CLI: surface"
assert_contains "version"       "$($BIN version)" "pideploy 1.0.0"
assert_contains "help commands" "$($BIN help)"    "init"
assert_contains "help serve"    "$($BIN help)"    "Tailscale"
assert_fail     "unknown cmd exits nonzero" "$BIN bogus-cmd"
assert_contains "unknown cmd errors to stderr" "$($BIN bogus-cmd 2>&1)" "unknown command"

grp "CLI: agent manual"
AG="$($BIN agent)"
assert_contains "agent: title"        "$AG" "Agent Operating Manual"
assert_contains "agent: architecture" "$AG" "self-hosted runner per repo"
assert_contains "agent: output contract" "$AG" "STDOUT"
assert_contains "agent: documents json errors" "$AG" '{"error":"<msg>","code":<N>}'
assert_contains "agent: lists skill command"   "$AG" 'pideploy skill'
assert_contains "agent: lists help command"    "$AG" 'pideploy help [command]'
assert_contains "agent: --skill flag"          "$AG" '--skill'
assert_contains "agent: explains label routing" "$AG" "label matching"
assert_contains "agent: documents deploy pipeline" "$AG" "Deploy pipeline"
assert_contains "agent: prereqs"      "$AG" "Prerequisites"
assert_contains "agent: quickstart"   "$AG" "Agent quickstart"
assert_contains "agent: troubleshoot" "$AG" "Troubleshooting"
assert_eq "--agent equals agent subcommand" "$($BIN --agent)" "$AG"
assert_absent "agent manual has no PII" "$AG" "@example"   # sanity: no stray addresses

grp "CLI: self-description, per-command help & skill"
assert_contains "usage: what-it-is"  "$($BIN help)" "WHAT IT IS"
assert_contains "usage: how-it-works" "$($BIN help)" "HOW IT WORKS"
assert_contains "usage: top-line agent directive" "$($BIN help)" "AI AGENTS: run \`pideploy --agent\`"
assert_contains "usage: getting started" "$($BIN help)" "GETTING STARTED"
assert_contains "usage: first step is setup" "$($BIN help)" "pideploy setup"
assert_contains "usage: agent section" "$($BIN help)" "FOR AI AGENTS"
assert_contains "usage: mentions --skill install" "$($BIN help)" "SKILL.md"
assert_contains "help <cmd>: init options" "$($BIN help init)" "--port"
assert_contains "help <cmd>: init documents --dotenv-secret" "$($BIN help init)" "--dotenv-secret"
assert_contains "help <cmd>: init describes --name" "$($BIN help init)" "stack"
assert_contains "help <cmd>: config keys" "$($BIN help config)" "default_port"
assert_contains "help <cmd>: config documents template" "$($BIN help config)" "config template"
# status help must match what status actually emits (target/deploy_host)
assert_contains "help status: documents target row"   "$($BIN help status)" "target"
assert_contains "help status: documents deploy_host json" "$($BIN help status)" "deploy_host"
assert_contains "<cmd> --help routes" "$($BIN serve --help)" "Tailscale"
assert_contains "-h routes to help"   "$($BIN status -h)" "status"
# completeness: EVERY dispatchable command resolves to a help section (no gaps)
for c in init onboard deploy status serve unserve logs config ports env rm setup doctor agent skill help version; do
  assert_ok "help section exists: $c" "$BIN help $c"
done
assert_fail     "help unknown cmd → error" "$BIN help nope"
SK="$($BIN skill)"
assert_contains "skill: frontmatter name"  "$SK" "name: pideploy"
assert_contains "skill: has description"   "$SK" "description:"
assert_contains "skill: directives/rules"  "$SK" "Rules / directives"
assert_contains "skill: troubleshooting"   "$SK" "Troubleshooting"
assert_contains "skill: references --agent" "$SK" "pideploy --agent"
assert_contains "skill: documents json errors" "$SK" '{"error":"<msg>","code":<N>}'
assert_contains "skill: reference lists skill+help" "$SK" 'help <cmd>'
assert_contains "skill: lists setup"        "$SK" "setup"
assert_contains "skill: explains routing"   "$SK" "How it routes"
assert_eq "--skill equals skill subcommand" "$($BIN --skill)" "$SK"
assert_absent "skill has no PII" "$SK" "@example"

grp "CLI: doctor & status (mocked env)"
assert_contains "doctor runs"        "$($BIN doctor 2>&1)" "docker-engine"
assert_contains "doctor checks gh"   "$($BIN doctor 2>&1)" "gh-auth"
assert_contains "doctor: passing checks marked ok" "$($BIN doctor 2>&1)" "ok"
assert_contains "status: runner row" "$($BIN status 2>&1)" "runner"
assert_contains "status: linger row" "$($BIN status 2>&1)" "linger"

# ════════════════════════════════════════════════════════════════════════════
grp "Integration: init → status → serve → deploy → rm (all mocked)"
REPO="$SBOX/proj"; mkdir -p "$REPO" "$SBOX/remote.git"
( cd "$SBOX/remote.git" && git init -q --bare )
( cd "$REPO" && git init -q && git remote add origin "$SBOX/remote.git" \
   && echo '{"name":"proj","scripts":{"start":"true"}}' > package.json \
   && git add -A && git commit -q -m init && git branch -M main && git push -q -u origin main )

OUT="$(cd "$REPO" && $BIN init --port 8080 2>&1)"
assert_contains "init: announces repo" "$OUT" "testuser/testrepo"
assert_file "init: Dockerfile created"   "$REPO/Dockerfile"
assert_file "init: compose created"      "$REPO/docker-compose.yml"
assert_file "init: workflow created"     "$REPO/.github/workflows/deploy.yml"
assert_contains "init: Dockerfile is node" "$(cat "$REPO/Dockerfile")" "FROM node:"
assert_contains "init: compose binds localhost" "$(cat "$REPO/docker-compose.yml")" "127.0.0.1:8080:8080"
assert_contains "init: compose has stack name"  "$(cat "$REPO/docker-compose.yml")" "name: testrepo"
assert_file     "init: .pideploy.conf created"   "$REPO/.pideploy.conf"
assert_contains "init: conf has app_name"        "$(cat "$REPO/.pideploy.conf")" "app_name=testrepo"
assert_contains "init: conf has port"            "$(cat "$REPO/.pideploy.conf")" "default_port=8080"
assert_absent   "init: conf has no secrets"      "$(cat "$REPO/.pideploy.conf")" "TOKEN"
assert_file     "init: .gitignore created"       "$REPO/.gitignore"
assert_contains "init: gitignore blocks .env"    "$(cat "$REPO/.gitignore")" ".env"
assert_contains "init: workflow has no PR trigger guard" "$(cat "$REPO/.github/workflows/deploy.yml")" "Do NOT"
assert_absent   "init: workflow has no pull_request" "$(cat "$REPO/.github/workflows/deploy.yml")" "pull_request:"
assert_contains "init: workflow self-hosted"    "$(cat "$REPO/.github/workflows/deploy.yml")" "self-hosted"
# regression: generated workflow MUST be valid YAML (the ${{ }}-in-flow-mapping bug)
assert_absent "init: workflow has no inline concurrency braces" "$(cat "$REPO/.github/workflows/deploy.yml")" "{ group:"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$REPO/.github/workflows/deploy.yml" 2>/dev/null \
    && ok "init: workflow is valid YAML" || bad "init: workflow is valid YAML" "GitHub Actions YAML did not parse"
else ok "init: workflow is valid YAML (skip: no pyyaml)"; fi
assert_contains "init: runner started msg"      "$OUT" "runner pi-testuser-testrepo"
assert_ok "init: runner registered dir exists"  "[ -d '$PIDEPLOY_HOME/runners/testuser-testrepo' ]"
assert_ok "init: runner marked active (state)"  "[ -f '$PIDEPLOY_STATE/testuser-testrepo' ]"
assert_contains "init: pushed" "$OUT" "pushed"
# pushed commit actually landed on the (local) remote
assert_contains "init: remote has deploy commit" "$(git --git-dir="$SBOX/remote.git" log --oneline 2>&1)" "pideploy"

ST="$(cd "$REPO" && $BIN status 2>&1)"
assert_contains "status: shows runner"        "$ST" "testuser-testrepo"
assert_contains "status: runner active"       "$ST" "active"
assert_contains "status: shows container"     "$ST" "myapp"

assert_contains "serve: prints https url" "$(cd "$REPO" && $BIN serve 8080 2>&1)" "https://test-pi.tailnet.ts.net/"
assert_ok       "unserve runs"            "(cd '$REPO' && $BIN unserve 8080)"
assert_contains "deploy: dispatches"      "$(cd "$REPO" && $BIN deploy 2>&1)" "dispatched"
# logs: defaults to the first running container and tails it
assert_contains "logs: tails first container" "$(cd "$REPO" && $BIN logs 2>&1)" "log line"
assert_contains "logs: accepts explicit app" "$(cd "$REPO" && $BIN logs myapp 2>&1)" "log line"

# idempotency: second init should skip registration, not error
OUT2="$(cd "$REPO" && $BIN init --port 8080 2>&1)"
assert_contains "init idempotent (skips runner)" "$OUT2" "already registered"
assert_contains "init idempotent (keeps Dockerfile)" "$OUT2" "kept existing Dockerfile"
# --yes is accepted as a no-op (CLI never prompts) and init exits 0 on success
assert_ok       "init: accepts --yes no-op, exits 0" "(cd '$REPO' && $BIN init --yes --port 8080)"

# rm deregisters
RM="$(cd "$REPO" && $BIN rm 2>&1 || true)"
assert_contains "rm: removes runner"  "$RM" "removed runner"
assert_ok "rm: runner dir gone"       "[ ! -d '$PIDEPLOY_HOME/runners/testuser-testrepo' ]"
assert_ok "rm: state cleared"         "[ ! -f '$PIDEPLOY_STATE/testuser-testrepo' ]"

# ════════════════════════════════════════════════════════════════════════════
grp "Port registry & collision guard"
rm -f "$PIDEPLOY_HOME/ports"   # clean slate for deterministic allocation
for nm in appa appb appc; do  # create 3 distinct pushable repos (no shared port)
  git init -q --bare "$SBOX/$nm.git" >/dev/null 2>&1
  git init -q "$SBOX/p-$nm" >/dev/null 2>&1
  git -C "$SBOX/p-$nm" remote add origin "$SBOX/$nm.git" 2>/dev/null
  echo '{"name":"x","scripts":{"start":"true"}}' > "$SBOX/p-$nm/package.json"
  git -C "$SBOX/p-$nm" add -A >/dev/null 2>&1
  git -C "$SBOX/p-$nm" commit -qm i >/dev/null 2>&1
  git -C "$SBOX/p-$nm" branch -M main >/dev/null 2>&1
  git -C "$SBOX/p-$nm" push -q -u origin main >/dev/null 2>&1
done
PA="$SBOX/p-appa"; PB="$SBOX/p-appb"; PC="$SBOX/p-appc"
portof() { grep -oE '127\.0\.0\.1:[0-9]+' "$1/docker-compose.yml" | head -1 | grep -oE '[0-9]+$'; }
# two DIFFERENT repos, neither passing --port → auto-assigned distinct ports
( cd "$PA" && MOCK_REPO=testuser/appa $BIN init --no-dotenv ) >/dev/null 2>&1
( cd "$PB" && MOCK_REPO=testuser/appb $BIN init --no-dotenv ) >/dev/null 2>&1
assert_eq "auto: first app gets default 8080"      "$(portof "$PA")" "8080"
assert_eq "auto: second app gets next free 8081"   "$(portof "$PB")" "8081"
assert_contains "registry records appa=8080"       "$(cat "$PIDEPLOY_HOME/ports")" "testuser-appa=8080"
assert_contains "registry records appb=8081"       "$(cat "$PIDEPLOY_HOME/ports")" "testuser-appb=8081"
assert_contains "ports cmd lists assignments"      "$($BIN ports)" "testuser-appb=8081"
assert_json     "ports --json valid"               "$($BIN ports --json)"
assert_struct   "ports --json maps repo→int"       "$($BIN ports --json)" "d['testuser-appb']==8081"
# explicit --port that is already taken by another repo → hard fail (exit 1)
assert_exit  "explicit --port collision → exit 1"  "(cd '$PC' && MOCK_REPO=testuser/appc $BIN init --port 8080 --no-dotenv)" 1
assert_contains "collision error names the port"   "$(cd "$PC" && MOCK_REPO=testuser/appc $BIN init --port 8080 --no-dotenv 2>&1 || true)" "already in use"
# stable: re-init the same repo (no --port) keeps its assigned port
( cd "$PA" && MOCK_REPO=testuser/appa $BIN init --no-dotenv ) >/dev/null 2>&1
assert_eq "stable: re-init reuses the same port"   "$(portof "$PA")" "8080"
# rm frees the port back into the pool
( cd "$PA" && MOCK_REPO=testuser/appa $BIN rm ) >/dev/null 2>&1
assert_absent "rm frees the port from registry"    "$(cat "$PIDEPLOY_HOME/ports" 2>/dev/null)" "testuser-appa="

# ════════════════════════════════════════════════════════════════════════════
grp "Secrets: no leakage"
SREPO="$SBOX/secret-proj"; mkdir -p "$SREPO" "$SBOX/sremote.git"
( cd "$SBOX/sremote.git" && git init -q --bare )
( cd "$SREPO" && git init -q && git remote add origin "$SBOX/sremote.git" \
   && echo '{"name":"s","scripts":{"start":"true"}}' > package.json \
   && git add -A && git commit -qm init && git branch -M main && git push -q -u origin main )
SENTINEL="SUPER_SECRET_SENTINEL_9f3xQ"
printf 'API_KEY=%s\n' "$SENTINEL" > "$SREPO/.env"
SOUT_ALL="$(cd "$SREPO" && $BIN init --port 8080 2>&1)"          # stdout + stderr together
assert_absent   "init output never contains the secret value"   "$SOUT_ALL" "$SENTINEL"
assert_absent   ".pideploy.conf has no secret value"            "$(cat "$SREPO/.pideploy.conf")" "$SENTINEL"
assert_contains ".pideploy.conf records only the secret NAME"   "$(cat "$SREPO/.pideploy.conf")" "dotenv_secret=PIDEPLOY_DOTENV"
assert_absent   "workflow has no secret value"                  "$(cat "$SREPO/.github/workflows/deploy.yml")" "$SENTINEL"
assert_contains "workflow references the secret by name"        "$(cat "$SREPO/.github/workflows/deploy.yml")" 'secrets.PIDEPLOY_DOTENV'
assert_contains "workflow removes .env after deploy"            "$(cat "$SREPO/.github/workflows/deploy.yml")" "rm -f .env"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$SREPO/.github/workflows/deploy.yml" 2>/dev/null \
    && ok "secrets workflow is valid YAML" || bad "secrets workflow is valid YAML" "did not parse"
else ok "secrets workflow is valid YAML (skip: no pyyaml)"; fi
assert_eq       ".env is NOT tracked by git"                    "$(cd "$SREPO" && git ls-files | grep -c '\.env$' || true)" "0"
assert_contains ".gitignore protects .env"                      "$(cat "$SREPO/.gitignore")" ".env"
assert_absent   "env command output never contains the value"   "$(cd "$SREPO" && $BIN env 2>&1)" "$SENTINEL"
assert_contains "env reports the secret name (stdout)"          "$(cd "$SREPO" && $BIN env 2>/dev/null)" "secret=PIDEPLOY_DOTENV"
assert_struct   "env --json shape & types"                      "$(cd "$SREPO" && $BIN env --json 2>/dev/null)" \
  "isinstance(d['secret'],str) and isinstance(d['repo'],str)"
assert_exit     "env without a .env → error (exit 1)"           "(cd '$SBOX/proj' && $BIN env)" 1
# --no-dotenv: even with a .env present, no secret step is emitted
NOENV="$SBOX/noenv-proj"; mkdir -p "$NOENV" "$SBOX/ne.git"; ( cd "$SBOX/ne.git" && git init -q --bare )
( cd "$NOENV" && git init -q && git remote add origin "$SBOX/ne.git" && echo '{}' > package.json \
   && printf 'X=%s\n' "$SENTINEL" > .env && git add package.json && git commit -qm i && git branch -M main && git push -q -u origin main )
( cd "$NOENV" && $BIN init --port 8080 --no-dotenv >/dev/null 2>&1 )
assert_absent   "--no-dotenv omits the provision step"          "$(cat "$NOENV/.github/workflows/deploy.yml")" "secrets."
assert_absent   "--no-dotenv: no secret value in workflow"      "$(cat "$NOENV/.github/workflows/deploy.yml")" "$SENTINEL"

# ════════════════════════════════════════════════════════════════════════════
grp "AI contract: JSON output"
assert_json "config --json is valid"  "$($BIN config list --json)"
assert_json "status --json is valid"  "$(cd "$REPO" && $BIN status --json 2>/dev/null)"
assert_json "doctor --json is valid"  "$($BIN doctor --json 2>/dev/null || true)"
assert_json "init --json is valid"    "$(cd "$REPO" && $BIN init --port 8080 --json 2>/dev/null)"
assert_json "serve --json is valid"   "$(cd "$REPO" && $BIN serve 8080 --json 2>/dev/null)"
assert_json "deploy --json is valid"  "$(cd "$REPO" && $BIN deploy --json 2>/dev/null)"

# strict structure & types
assert_struct "status: shape" "$(cd "$REPO" && $BIN status --json 2>/dev/null)" \
  "isinstance(d['runners'],list) and isinstance(d['stacks'],list) and isinstance(d['serve'],list) and isinstance(d['linger'],bool)"
assert_struct "status: runner objects typed" "$(cd "$REPO" && $BIN status --json 2>/dev/null)" \
  "all(isinstance(r['name'],str) and isinstance(r['active'],bool) for r in d['runners'])"
assert_struct "status: stack objects typed" "$(cd "$REPO" && $BIN status --json 2>/dev/null)" \
  "all({'name','status','ports'} <= set(s) for s in d['stacks'])"
assert_struct "init: shape & types" "$(cd "$REPO" && $BIN init --port 8080 --json 2>/dev/null)" \
  "d['repo']=='testuser/testrepo' and isinstance(d['port'],int) and isinstance(d['pushed'],bool) and isinstance(d['runner_registered'],bool) and isinstance(d['files'],list)"
assert_struct "doctor: shape & types" "$($BIN doctor --json 2>/dev/null || true)" \
  "isinstance(d['ok'],bool) and all(isinstance(c['ok'],bool) and c['severity'] in ('fatal','warn') for c in d['checks'])"
assert_struct "serve: shape & types" "$(cd "$REPO" && $BIN serve 8080 --json 2>/dev/null)" \
  "d['url'].startswith('https://') and isinstance(d['port'],int)"
assert_struct "deploy: dispatched bool" "$(cd "$REPO" && $BIN deploy --json 2>/dev/null)" \
  "d['dispatched'] is True"
assert_struct "config: all values strings" "$($BIN config list --json)" \
  "all(isinstance(v,str) for v in d.values())"

grp "AI contract: streams & exit codes"
# data on stdout, progress on stderr
SOUT="$(cd "$REPO" && $BIN init --port 8080 2>/dev/null)"
assert_contains "init stdout carries data"     "$SOUT" "repo=testuser/testrepo"
assert_absent   "init stdout has no progress"  "$SOUT" "pideploy:"
assert_contains "serve stdout is the url"       "$(cd "$REPO" && $BIN serve 8080 2>/dev/null)" "https://test-pi.tailnet.ts.net/"
# exit codes: 0 ok · 1 runtime · 2 usage
assert_exit "doctor exits 0 when healthy"  "$BIN doctor" 0
assert_exit "usage error (missing key) → 2" "$BIN config get" 2
assert_exit "unknown command → 2"           "$BIN bogus-cmd" 2
assert_exit "serve without port → 2"        "$BIN serve" 2
assert_ok   "setup runs"                    "$BIN setup"

grp "AI contract: error shape"
# text mode: 'error: ...' on stderr
assert_contains "text error prefix"  "$($BIN bogus-cmd 2>&1 1>/dev/null)" "error: unknown command"
# json mode: a valid JSON error object on stderr...
EJSON="$($BIN bogus-cmd --json 2>&1 1>/dev/null)"
assert_json     "json error is valid JSON" "$EJSON"
assert_struct   "json error shape"  "$EJSON" "isinstance(d['error'],str) and d['code']==2"
# ...and STDOUT stays empty on error
assert_eq       "error: stdout empty (text)" "$($BIN bogus-cmd 2>/dev/null)" ""
assert_eq       "error: stdout empty (json)" "$($BIN bogus-cmd --json 2>/dev/null)" ""
# runtime error (missing dep) → 'missing dependency' message, exit 1
assert_contains "missing-dep error (text)" "$(lib 'need no-such-binary-xyz 2>&1 || true')" "missing dependency"
assert_struct   "missing-dep error (json)" "$(lib 'FORMAT=json; need no-such-binary-xyz 2>&1 1>/dev/null || true')" \
  "isinstance(d['error'],str) and 'dependency' in d['error'] and d['code']==1"

grp "Guards"
assert_fail "init outside a git repo fails"  "(cd '$SBOX' && $BIN init)"
assert_exit "init unknown flag → usage (2)"  "(cd '$REPO' && $BIN init --bogus)" 2
assert_exit "config set without value → 2"   "$BIN config set onlykey" 2

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n%s────────────────────────────────────────%s\n' "$c_d" "$c_0"
if [ "$FAIL" -eq 0 ]; then
  printf '%s✓ all %d checks passed%s\n' "$c_g$c_b" "$PASS" "$c_0"; exit 0
else
  printf '%s✗ %d passed, %d failed%s\n' "$c_r$c_b" "$PASS" "$FAIL" "$c_0"; exit 1
fi
