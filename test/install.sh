#!/bin/bash
# Checks install.sh and --uninstall against throwaway home folders, so the real
# ~/.claude.json, settings.json and shared Chrome are never touched. Each case
# uses its own profile and port; one case starts (and quits) a background Chrome.
#
#   test/install.sh

set -u
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO_DIR/install.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/shared-chrome-install-test.XXXXXX")"
trap 'pkill -f -- "--user-data-dir=$WORK/" 2>/dev/null; rm -rf "$WORK"' EXIT
DENY="mcp__plugin_chrome-devtools-mcp_chrome-devtools"
PRIOR='{"type":"stdio","command":"/bin/echo","args":["prior"],"env":{}}'

failures=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; failures=$((failures + 1)); fi; }
# Runs install.sh with HOME pointed at a sandbox. Output goes to $WORK/last.log.
run() { local home="$1"; shift; env HOME="$home" "$@" > "$WORK/last.log" 2>&1; RC=$?; }
server() { jq -c '.mcpServers["chrome-devtools"] // null' "$1/.claude.json" 2>/dev/null || echo null; }
backups() { grep -c 'backed up' "$WORK/last.log"; }

echo "sandbox: $WORK"
echo
echo "--- existing config: symlinked settings, an earlier server, overrides"
A="$WORK/a"; mkdir -p "$A/.claude" "$A/real"
echo '{"permissions":{"allow":["Bash(ls)"]},"theme":"dark"}' > "$A/real/settings.json"
chmod 0640 "$A/real/settings.json"
ln -s ../real/settings.json "$A/.claude/settings.json"
cp "$A/real/settings.json" "$WORK/a-settings.orig"
jq -n --argjson s "$PRIOR" '{numStartups: 3, mcpServers: {"chrome-devtools": $s}}' > "$A/.claude.json"
OVR=(CHROME_MCP_PORT=9461 CHROME_MCP_PROFILE="$A/profile")

run "$A" "${OVR[@]}" "$INSTALL"
check "install succeeds" '[ $RC -eq 0 ] || ! cat "$WORK/last.log"'
check "server points at the wrapper and carries the overrides" \
  'server "$A" | jq -e --arg c "$A/.claude/chrome-mcp/chrome-mcp-shared.sh" --arg p "$A/profile" \
     ".command == \$c and .env == {CHROME_MCP_PORT: \"9461\", CHROME_MCP_PROFILE: \$p}" >/dev/null'
check "deny rule added, existing settings kept" \
  'jq -e --arg r "$DENY" "(.permissions.deny | index(\$r)) and .theme == \"dark\" and .permissions.allow == [\"Bash(ls)\"]" "$A/real/settings.json" >/dev/null'
check "settings.json is still a symlink, mode 0640" '[ -L "$A/.claude/settings.json" ] && [ "$(/usr/bin/stat -f %Lp "$A/real/settings.json")" = 640 ]'
check "state records the earlier server" '[ "$(jq -c .prior_server "$A/.claude/chrome-mcp/install-state.json")" = "$PRIOR" ]'

run "$A" "${OVR[@]}" "$INSTALL"
check "re-running changes nothing and makes no backups" '[ "$(backups)" = 0 ]'
check "the registered overrides win over the shell's" \
  '[ "$(HOME="$A" CHROME_MCP_PORT=1 bash -c ". \"\$1\" && use_registered_overrides && echo \"\$PORT\"" _ "$REPO_DIR/bin/common.sh")" = 9461 ]'

run "$A" "${OVR[@]}" "$A/.claude/chrome-mcp/ensure-chrome.sh"
check "the installed launcher starts Chrome with the overrides" 'pgrep -f -- "--user-data-dir=$A/profile" >/dev/null'

# Make restoring the earlier server fail part-way through.
STATE="$A/.claude/chrome-mcp/install-state.json"
cp "$STATE" "$WORK/state.good"
jq '.prior_server = {"type": "nonsense"}' "$WORK/state.good" > "$STATE"
run "$A" "$INSTALL" --uninstall
check "a failing uninstall exits non-zero" '[ $RC -ne 0 ]'
check "...and keeps install-state.json for a re-run" '[ -f "$STATE" ]'
cp "$WORK/state.good" "$STATE"

run "$A" "$INSTALL" --uninstall
check "re-running uninstall (overrides not set in the shell) succeeds" '[ $RC -eq 0 ] || ! cat "$WORK/last.log"'
check "the earlier server is restored" '[ "$(server "$A")" = "$PRIOR" ]'
check "settings restored exactly" 'diff <(jq -S . "$WORK/a-settings.orig") <(jq -S . "$A/real/settings.json") >/dev/null'
check "settings.json is still a symlink, mode 0640" '[ -L "$A/.claude/settings.json" ] && [ "$(/usr/bin/stat -f %Lp "$A/real/settings.json")" = 640 ]'
check "other ~/.claude.json keys kept" '[ "$(jq .numStartups "$A/.claude.json")" = 3 ]'
check "the override Chrome was quit" '! pgrep -f -- "--user-data-dir=$A/profile" >/dev/null'
check "install folder removed, profile kept" '[ ! -e "$A/.claude/chrome-mcp" ] && [ -d "$A/profile" ]'

echo
echo "--- no config at all"
B="$WORK/b"; mkdir -p "$B"
run "$B" CHROME_MCP_PORT=9462 CHROME_MCP_PROFILE="$B/profile" "$INSTALL"
check "install succeeds" '[ $RC -eq 0 ] || ! cat "$WORK/last.log"'
check "settings.json created with just the deny rule" \
  '[ "$(jq -c . "$B/.claude/settings.json")" = "{\"permissions\":{\"deny\":[\"$DENY\"]}}" ]'
run "$B" "$INSTALL" --uninstall
check "uninstall succeeds" '[ $RC -eq 0 ] || ! cat "$WORK/last.log"'
check "the settings.json install created is removed (after a backup)" \
  '[ ! -e "$B/.claude/settings.json" ] && ls "$B/.claude/"settings.json.bak-shared-chrome-* >/dev/null 2>&1'
check "no chrome-devtools server left" '[ "$(server "$B")" = null ]'

echo
echo "--- the deny rule was already there before install"
C="$WORK/c"; mkdir -p "$C/.claude"
jq -n --arg r "$DENY" '{permissions: {deny: [$r]}}' > "$C/.claude/settings.json"
run "$C" CHROME_MCP_PORT=9463 CHROME_MCP_PROFILE="$C/profile" "$INSTALL"
check "install succeeds" '[ $RC -eq 0 ] || ! cat "$WORK/last.log"'
run "$C" "$INSTALL" --uninstall
check "uninstall keeps the deny rule it didn't add" \
  'jq -e --arg r "$DENY" ".permissions.deny == [\$r]" "$C/.claude/settings.json" >/dev/null'

echo
echo "--- a different chrome-devtools server registered at uninstall time"
D="$WORK/d"; mkdir -p "$D"
run "$D" CHROME_MCP_PORT=9464 CHROME_MCP_PROFILE="$D/profile" "$INSTALL"
HOME="$D" claude mcp remove --scope user chrome-devtools >/dev/null 2>&1
HOME="$D" claude mcp add-json --scope user chrome-devtools '{"type":"stdio","command":"/bin/echo","args":["someone else"],"env":{}}' >/dev/null
run "$D" "$INSTALL" --uninstall
check "uninstall leaves a server that isn't ours alone" '[ "$(server "$D" | jq -r ".args[0]")" = "someone else" ]'

echo
[ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed"
exit $(( failures > 0 ))
