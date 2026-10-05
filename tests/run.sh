#!/usr/bin/env bash
# Tests for bin/archive.sh, bin/cards.sh and bin/validate-card.sh.
# Runs against a throwaway HOME; never touches real notifications or plugins.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$HERE/bin/archive.sh"
CARDS="$HERE/bin/cards.sh"
VALIDATE="$HERE/bin/validate-card.sh"
ID="io.github.linuskelsey.omahub"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
eq()   { local name="$1" want="$2" got="$3"; if [[ "$want" == "$got" ]]; then ok "$name"; else bad "$name (want '$want', got '$got')"; fi; }

fresh_env() {
  TMP="$(mktemp -d)"
  export HOME="$TMP/home" XDG_STATE_HOME="$TMP/home/.local/state"
  SRC="$HOME/.local/state/omarchy/notifications"
  DST="$XDG_STATE_HOME/$ID"
  mkdir -p "$SRC/history" "$SRC/images"
}
notif() { # notif <dir> <stem> <app> <summary> [appIcon]
  jq -nc --arg app "$3" --arg s "$4" --arg icon "${5:-}" --argjson ts "${2%%-*}" \
    '{id:1,originalId:1,app:$app,appIcon:$icon,summary:$s,body:"b",image:"",glyph:"",execArgv:"",urgency:1,expireTimeout:0,timestamp:$ts}' \
    > "$1/$2.json"
}
count() { "$ARCHIVE" list | jq '.items | length'; }

echo "archive.sh"
fresh_env
notif "$SRC/history" 1700000000001-1 Mail "older"
notif "$SRC/history" 1700000000002-2 Mail "newer"
"$ARCHIVE" sync
eq "history entries are archived" 2 "$(count)"
eq "newest first" newer "$("$ARCHIVE" list | jq -r '.items[0].summary')"
eq "stem is attached" 1700000000002-2 "$("$ARCHIVE" list | jq -r '.items[0].stem')"

notif "$SRC" 1700000000003-3 Chat "live toast"
"$ARCHIVE" sync
eq "live toast is archived immediately" 3 "$(count)"
cp "$SRC/1700000000003-3.json" "$SRC/history/"
"$ARCHIVE" sync
eq "same toast arriving in history does not duplicate" 3 "$(count)"

"$ARCHIVE" remove 1700000000002-2
eq "remove drops the entry" 2 "$(count)"
"$ARCHIVE" sync
eq "removed entry is not resurrected by sync" 2 "$(count)"
check "remove rejects a path-like stem" bash -c "! '$ARCHIVE' remove '../etc/passwd'"
check "remove rejects an empty stem" bash -c "! '$ARCHIVE' remove ''"

notif "$SRC/history" 1700000000010-10 Remote "tracker" "http://203.0.113.9/pixel.png"
notif "$SRC/history" 1700000000011-11 Remote "tracker2" "https://example.invalid/i.png"
notif "$SRC/history" 1700000000012-12 Local "themed" "firefox"
notif "$SRC/history" 1700000000013-13 Local "path" "file:///usr/share/icons/x.png"
"$ARCHIVE" sync
eq "http appIcon is not archived" "" "$("$ARCHIVE" list | jq -r '.items[] | select(.summary=="tracker") | .appIcon')"
eq "https appIcon is not archived" "" "$("$ARCHIVE" list | jq -r '.items[] | select(.summary=="tracker2") | .appIcon')"
eq "themed icon name is kept" firefox "$("$ARCHIVE" list | jq -r '.items[] | select(.summary=="themed") | .appIcon')"
eq "file:// icon is kept" "file:///usr/share/icons/x.png" "$("$ARCHIVE" list | jq -r '.items[] | select(.summary=="path") | .appIcon')"
"$ARCHIVE" remove 1700000000010-10; "$ARCHIVE" remove 1700000000011-11; "$ARCHIVE" remove 1700000000012-12; "$ARCHIVE" remove 1700000000013-13

"$ARCHIVE" clear
eq "clear empties the archive" 0 "$(count)"
"$ARCHIVE" sync
eq "cleared entries are not resurrected" 0 "$(count)"
check "sync on an empty archive succeeds (watcher-crash regression)" "$ARCHIVE" sync

echo "archive.sh: images"
fresh_env
printf 'PNG' > "$SRC/images/1700000000010-4-appIcon"
notif "$SRC/history" 1700000000010-4 Chat "with icon" "file://$SRC/images/1700000000010-4-appIcon"
notif "$SRC/history" 1700000000011-5 Evil "traversal" "file://$SRC/images/../../../etc/passwd"
"$ARCHIVE" sync
icon="$("$ARCHIVE" list | jq -r '.items[] | select(.stem=="1700000000010-4") | .appIcon')"
eq "icon is rewritten into the archive" "file://$DST/images/1700000000010-4-appIcon" "$icon"
check "icon file was copied" test -f "$DST/images/1700000000010-4-appIcon"
evil="$("$ARCHIVE" list | jq -r '.items[] | select(.stem=="1700000000011-5") | .appIcon')"
eq "path traversal in appIcon is not followed" "file://$SRC/images/../../../etc/passwd" "$evil"
check "nothing outside the images dir was copied" bash -c "[[ \$(ls '$DST/images' | wc -l) -eq 1 ]]"

echo "archive.sh: retention"
fresh_env
notif "$SRC/history" 1700000000020-6 Mail "old"
"$ARCHIVE" sync
# Age the archived copy AND its source, as real time passing would.
touch -d '40 days ago' "$DST/items/1700000000020-6.json" "$SRC/history/1700000000020-6.json"
"$ARCHIVE" sync
"$ARCHIVE" sync   # the aged source is still in the daemon's history: it must not come back
eq "entries older than 30 days are removed and stay removed" 0 "$(count)"
rm -f "$SRC/history/1700000000020-6.json"
notif "$SRC/history" 1700000000021-7 Mail "old but kept"
"$ARCHIVE" clear; rm -f "$DST/dismissed"
echo '{"retentionDays": 60}' > "$DST/config.json"
"$ARCHIVE" sync
touch -d '40 days ago' "$DST/items/1700000000021-7.json" "$SRC/history/1700000000021-7.json"
"$ARCHIVE" sync
eq "retentionDays in config.json is honoured" 1 "$(count)"

echo "archive.sh: cap"
fresh_env
for i in $(seq 1 205); do notif "$SRC/history" "$((1700000100000 + i))-$i" Bulk "n$i"; done
"$ARCHIVE" sync
eq "archive is capped at 200 entries" 200 "$(count)"
eq "the newest are kept" n205 "$("$ARCHIVE" list | jq -r '.items[0].summary')"

echo "archive.sh: dependencies"
fresh_env
mkdir -p "$TMP/bare" && ln -s "$(command -v bash)" "$TMP/bare/bash"
PATH="$TMP/bare" bash "$ARCHIVE" list >/dev/null 2>"$TMP/err"; rc=$?
eq "missing jq/inotifywait exits 3" 3 "$rc"
check "…with a message naming the dependency" grep -q "needs" "$TMP/err"

echo "cards.sh"
fresh_env
P="$HOME/.config/omarchy/plugins"
mkdir -p "$P/good" "$P/good.bak" "$P/traversal" "$P/absolute" "$P/notqml" "$P/none" "$P/future"
echo '{"id":"good","name":"Good","hubCard":{"entry":"Card.qml","title":"Good Card"}}' > "$P/good/manifest.json"
cp "$P/good/manifest.json" "$P/good.bak/manifest.json"   # a backup copy with the same id
echo '{"id":"traversal","name":"T","hubCard":{"entry":"../x.qml"}}' > "$P/traversal/manifest.json"
echo '{"id":"absolute","name":"A","hubCard":{"entry":"/etc/x.qml"}}' > "$P/absolute/manifest.json"
echo '{"id":"notqml","name":"N","hubCard":{"entry":"run.sh"}}' > "$P/notqml/manifest.json"
echo '{"id":"none","name":"No card"}' > "$P/none/manifest.json"
echo '{"id":"future","name":"F","hubCard":{"entry":"Card.qml","contract":2}}' > "$P/future/manifest.json"
out="$("$CARDS")"
eq "only valid cards are discovered" "future good" "$(echo "$out" | jq -r 'map(.id) | sort | join(" ")')"
eq "a folder not named after its id (e.g. .bak) is ignored" 1 "$(echo "$out" | jq '[.[] | select(.id=="good")] | length')"
eq "entry is an absolute path" "$P/good/Card.qml" "$(echo "$out" | jq -r '.[] | select(.id=="good") | .entry')"
eq "contract defaults to 1" 1 "$(echo "$out" | jq -r '.[] | select(.id=="good") | .contract')"
eq "a declared contract is passed through" 2 "$(echo "$out" | jq -r '.[] | select(.id=="future") | .contract')"
eq "the title is used" "Good Card" "$(echo "$out" | jq -r '.[] | select(.id=="good") | .title')"

echo "validate-card.sh"
fresh_env
# The template ships its manifest as manifest.example.json: the marketplace treats any
# manifest.json one folder deep as a second plugin, so a real one would fail submission.
instantiate() { cp -r "$HERE/template" "$1"; mv "$1/manifest.example.json" "$1/manifest.json"; }
check "the repo has exactly one manifest.json a marketplace scan would find" bash -c "[[ \$(cd '$HERE' && git ls-files | grep -ciE '^([^/]+/)?manifest\.json\$') -eq 1 ]]"
instantiate "$TMP/tpl"
check "the instantiated template passes" "$VALIDATE" "$TMP/tpl"
bad_plugin="$TMP/bad"; instantiate "$bad_plugin"
sed -i 's/implicitHeight/somethingElse/g' "$bad_plugin/Card.qml"
check "a card without implicitHeight fails" bash -c "! '$VALIDATE' '$bad_plugin'"
instantiate "$TMP/linked"; ln -s /etc/hostname "$TMP/linked/leak"
check "a plugin containing a symlink fails" bash -c "! '$VALIDATE' '$TMP/linked'"
instantiate "$TMP/nokey"; jq 'del(.hubCard)' "$TMP/nokey/manifest.json" > "$TMP/m" && cp "$TMP/m" "$TMP/nokey/manifest.json"
check "a manifest without hubCard fails" bash -c "! '$VALIDATE' '$TMP/nokey'"

echo "uninstall.sh"
fresh_env
notif "$SRC/history" 1700000000030-8 Mail "to wipe"
"$ARCHIVE" sync
check "archive exists before uninstall" test -d "$DST/items"
"$HERE/bin/uninstall.sh" --yes >/dev/null
check "uninstall removes the state directory" bash -c "! test -e '$DST'"
check "uninstall with nothing to delete succeeds" "$HERE/bin/uninstall.sh" --yes
mkdir -p "$TMP/elsewhere"; ln -s "$TMP/elsewhere" "$DST"
check "uninstall refuses a symlinked state dir" bash -c "! '$HERE/bin/uninstall.sh' --yes"
check "…and leaves the link target alone" test -d "$TMP/elsewhere"

echo
echo "$pass passed, $fail failed"
((fail == 0))
