#!/bin/bash
# Install (or uninstall) the shared-Chrome wrapper for the Chrome DevTools MCP.
#
#   ./install.sh              install / update (safe to re-run)
#   ./install.sh --uninstall  undo the install and quit the shared Chrome (keeps
#                             the Chrome profile so logins survive a reinstall)
#
# What install does:
#   1. Copies bin/ (wrapper, lazy-launch relay, ensure-chrome, common) to
#      ~/.local/share/shared-chrome-mcp/, and saves any CHROME_MCP_* overrides
#      there (config.env) for every MCP client
#   2. npm-installs chrome-devtools-mcp@$MCP_VERSION into that folder
#   If Claude Code is installed:
#   3. Registers a user-scope MCP server "chrome-devtools" pointing at the wrapper
#   4. Adds a deny rule hiding the chrome-devtools plugin's own MCP server
#      (the plugin stays enabled so its skills still load)
# Other MCP clients are registered by hand (README, "Other MCP clients").
# Each config file is backed up before it is changed. The first install records
# what it changed in install-state.json, so uninstall restores the config exactly.

set -euo pipefail

MCP_VERSION="${MCP_VERSION:-1.9.0}"
DENY_RULE="mcp__plugin_chrome-devtools-mcp_chrome-devtools"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$REPO_DIR/bin/common.sh"
WRAPPER="$INSTALL_DIR/chrome-mcp-shared.sh"
STATE="$INSTALL_DIR/install-state.json"
# Where installs before 1.0.0 lived.
LEGACY_DIR="$HOME/.claude/chrome-mcp"
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_JSON="$HOME/.claude.json"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
has_claude() { command -v claude >/dev/null; }

backup() {
  [ -f "$1" ] || return 0
  local dest="$1.bak-shared-chrome-$(date +%Y%m%d%H%M%S)"
  cp "$1" "$dest"
  say "backed up $1 -> $dest"
}

# Rewrite settings.json through a jq filter. The new file is written next to
# the real file (following a symlink) with the same permissions, then renamed
# over it, so the change is atomic and the symlink and mode survive.
edit_settings() {
  local real tmp
  real="$(/bin/realpath "$SETTINGS")"
  tmp="$(mktemp "$real.XXXXXX")"
  if jq "$@" "$real" > "$tmp"; then
    chmod "$(/usr/bin/stat -f %Lp "$real")" "$tmp"
    mv "$tmp" "$real"
  else
    rm -f "$tmp"
    die "could not update $SETTINGS"
  fi
}

has_deny_rule() { [ -f "$SETTINGS" ] && jq -e --arg r "$DENY_RULE" '(.permissions.deny // []) | index($r)' "$SETTINGS" >/dev/null; }
# A field of install-state.json, or null without one.
install_state() { jq -c "$1" "$STATE" 2>/dev/null || echo null; }
# The user-scope Claude Code server registered under SERVER_NAME, as JSON (null if none).
registered_server() { jq -c --arg n "$SERVER_NAME" '.mcpServers[$n] // null' "$CLAUDE_JSON" 2>/dev/null || echo null; }
is_our_server() {
  case "$(jq -r '.command // ""' <<<"$1")" in
    "$WRAPPER"|"$LEGACY_DIR/chrome-mcp-shared.sh") return 0 ;;
    *) return 1 ;;
  esac
}
wanted_server() { jq -cn --arg c "$WRAPPER" '{type: "stdio", command: $c, args: [], env: {}}'; }

# Save the overrides in force (this shell's, else the saved ones) for every client.
write_config() {
  local var tmp
  tmp="$(mktemp "$CONFIG.XXXXXX")"
  echo "# Written by install.sh: KEY=value, no quotes. A value set in the environment wins." > "$tmp"
  for var in "${OVERRIDE_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then echo "$var=${!var}" >> "$tmp"; fi
  done
  mv "$tmp" "$CONFIG"
}

# Bring an install from before 1.0.0 (in ~/.claude/chrome-mcp) to INSTALL_DIR:
# its record of what install changed, its log, and the overrides it registered
# in Claude Code. The old folder is removed once the new install is in place.
migrate_legacy() {
  [ -d "$LEGACY_DIR" ] || return 0
  mkdir -p "$INSTALL_DIR"
  local f env server
  for f in install-state.json wrapper.log; do
    if [ -f "$LEGACY_DIR/$f" ] && [ ! -f "$INSTALL_DIR/$f" ]; then cp "$LEGACY_DIR/$f" "$INSTALL_DIR/$f"; fi
  done
  if [ ! -f "$CONFIG" ]; then
    server="$(registered_server)"
    if is_our_server "$server"; then env="$(jq -c '.env // {}' <<<"$server")"; else env="$(install_state '.registered_env // {}')"; fi
    eval "$(jq -r 'objects | to_entries[] | select(.key as $k | $ARGS.positional | index($k))
      | "[ -n \"${\(.key):-}\" ] || export \(.key)=\(.value | @sh)"' --args "${OVERRIDE_VARS[@]}" <<<"$env")"
    write_config
    . "$REPO_DIR/bin/common.sh"
  fi
  say "moved the install from $LEGACY_DIR to $INSTALL_DIR"
}

# Runs with set -e in force: if restoring anything fails, it stops before
# deleting install-state.json, so it can be fixed and re-run.
uninstall() {
  command -v jq >/dev/null || die "'jq' is required but not on PATH"
  migrate_legacy

  if has_claude; then
    local server prior
    server="$(registered_server)"
    if is_our_server "$server"; then
      backup "$CLAUDE_JSON"
      say "removing user-scope MCP server '$SERVER_NAME'"
      claude mcp remove --scope user "$SERVER_NAME" >/dev/null
      server=null
    elif [ "$server" != "null" ]; then
      warn "server '$SERVER_NAME' isn't this setup's wrapper — leaving it alone"
    fi
    # Also runs on a re-run after a failed restore, when nothing is registered.
    prior="$(install_state .prior_server)"
    if [ "$server" = "null" ] && [ "$prior" != "null" ]; then
      claude mcp add-json --scope user "$SERVER_NAME" "$prior" >/dev/null
      say "restored the '$SERVER_NAME' server that was registered before install"
    fi

    # Without a state file (an install older than it), assume the rule was ours.
    if has_deny_rule && [ "$(install_state .deny_added)" != "false" ]; then
      backup "$SETTINGS"
      edit_settings --arg r "$DENY_RULE" --argjson p "$(install_state .permissions_created)" '
        .permissions.deny -= [$r]
        | if .permissions.deny == [] then del(.permissions.deny) else . end
        | if $p == true and .permissions == {} then del(.permissions) else . end'
      say "removed deny rule from $SETTINGS"
    fi
    if [ "$(install_state .settings_created)" = "true" ] && [ "$(jq -c . "$SETTINGS" 2>/dev/null)" = "{}" ]; then
      backup "$SETTINGS"
      rm -f "$SETTINGS"
      say "removed $SETTINGS (install created it)"
    fi
  elif [ -f "$STATE" ]; then
    die "install changed Claude Code's config, but 'claude' isn't on PATH to undo it"
  fi

  local pids
  pids="$(shared_chrome_pids)"
  if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    say "quit the shared Chrome"
  fi
  rm -rf "$INSTALL_DIR" "$LEGACY_DIR"
  say "removed $INSTALL_DIR (Chrome profile kept at $PROFILE)"
  say "done — remove '$SERVER_NAME' from any other MCP client you added it to, and restart their sessions"
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

# --- preflight -------------------------------------------------------------
[ "$(uname)" = "Darwin" ] || die "macOS only (the wrapper uses /usr/bin/lockf and the macOS Chrome path)"
for cmd in node npm jq curl lsof; do
  command -v "$cmd" >/dev/null || die "'$cmd' is required but not on PATH"
done
[ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ] || die "Node 22 or newer is required (found $(node --version))"
migrate_legacy
[ -x "$CHROME" ] || die "Chrome not found at $CHROME (set CHROME_MCP_CHROME to its binary)"
if chrome_answers && ! port_is_ours; then
  die "port $PORT is already in use by another program — re-run with CHROME_MCP_PORT=<free port>"
fi
if has_claude; then
  [ ! -f "$SETTINGS" ] || jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON — fix it first"
fi

# Record what was in Claude Code's config before the first install, for
# uninstall. An existing server that is already our wrapper means an install
# older than this file.
if has_claude && [ ! -f "$STATE" ]; then
  server="$(registered_server)"
  legacy=false
  if is_our_server "$server"; then server=null; legacy=true; fi
  if [ -f "$SETTINGS" ]; then settings_created=false; else settings_created=true; fi
  if [ -f "$SETTINGS" ] && jq -e 'has("permissions")' "$SETTINGS" >/dev/null; then permissions_created=false; else permissions_created=true; fi
  if has_deny_rule && [ "$legacy" = false ]; then deny_added=false; else deny_added=true; fi
  pending_state="$(jq -n --argjson s "$server" --argjson sc "$settings_created" \
    --argjson pc "$permissions_created" --argjson da "$deny_added" \
    '{prior_server: $s, settings_created: $sc, permissions_created: $pc, deny_added: $da}')"
fi

# --- 1 + 2: wrapper, saved overrides and MCP package ----------------------
say "installing wrapper to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
install -m 0755 "$REPO_DIR/bin/chrome-mcp-shared.sh" "$REPO_DIR/bin/ensure-chrome.sh" "$INSTALL_DIR/"
install -m 0644 "$REPO_DIR/bin/lazy-launch.cjs" "$REPO_DIR/bin/common.sh" "$INSTALL_DIR/"
write_config
if [ -n "${pending_state:-}" ]; then echo "$pending_state" > "$STATE"; fi

say "installing chrome-devtools-mcp@$MCP_VERSION"
npm install --silent --no-audit --no-fund --prefix "$INSTALL_DIR" "chrome-devtools-mcp@$MCP_VERSION"
[ -x "$INSTALL_DIR/node_modules/.bin/chrome-devtools-mcp" ] || die "npm install did not produce chrome-devtools-mcp"

if has_claude; then
  # --- 3: Claude Code user-scope MCP server -------------------------------
  wanted="$(wanted_server)"
  if jq -en --argjson a "$(registered_server)" --argjson b "$wanted" '$a == $b' >/dev/null; then
    say "Claude Code MCP server '$SERVER_NAME' already registered"
  else
    backup "$CLAUDE_JSON"
    claude mcp remove --scope user "$SERVER_NAME" >/dev/null 2>&1 || true
    say "registering Claude Code MCP server '$SERVER_NAME'"
    claude mcp add-json --scope user "$SERVER_NAME" "$wanted" >/dev/null
  fi

  # --- 4: hide the Claude plugin's own server -----------------------------
  if has_deny_rule; then
    say "deny rule already present in $SETTINGS"
  else
    mkdir -p "$(dirname "$SETTINGS")"
    if [ -f "$SETTINGS" ]; then backup "$SETTINGS"; else echo '{}' > "$SETTINGS"; fi
    edit_settings --arg r "$DENY_RULE" '.permissions.deny = ((.permissions.deny // []) + [$r])'
    say "added deny rule '$DENY_RULE' to $SETTINGS"
  fi
else
  say "Claude Code not found; skipped registering with it"
fi
rm -rf "$LEGACY_DIR"

say "installed. Next:"
cat <<EOF
   - Other MCP clients (Codex, Gemini CLI, …): register a stdio server named
     '$SERVER_NAME' with the command below. See "Other MCP clients" in README.md.
       $WRAPPER
   - Restart any open sessions (they keep their old MCP config).
   - Verify:  $REPO_DIR/test/all.sh   (with the shared Chrome closed)
   - Log into the sites you test (WP admin etc.) once in the shared Chrome;
     every session reuses those logins.
EOF
