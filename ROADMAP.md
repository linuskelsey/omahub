# Roadmap

Rough order, not promises.

## Soon

- **Skip shortcuts that are already bound.** Before registering its shortcuts, read Hyprland's bind table and leave any key something else already uses alone, reporting the conflict in settings (Stage Control does this). Two copies of the hub registering the same default shortcuts is a situation that crashed Hyprland 0.56.2 during development: removing one copy's shortcuts while the other's exist took the compositor down in its Lua keybind code. Until this lands, don't run two copies of the hub at the same time.
- **Test on a Hyprland using the old (non-Lua) config format**, and decide whether shortcuts need a different registration path there.
- **Single watcher across monitors**: share one archive watcher and one set of card backends instead of one per bar.

## Next

- **Urgent notifications**: style critical notifications differently (and optionally pin them to the top).
- **Keyboard navigation** inside the panel (arrows between notifications and cards, Enter to act, Delete to dismiss).
- **Notification images** (not just the app icon).
- **Do Not Disturb** quick toggle in the hub.
- **Minimum-version check** at startup, warning when Omarchy is older than the tested version.
- **Drag to reorder** cards in settings.
- **Automated checks**: run `tests/run.sh` and the marketplace validator in CI, and add UI-level tests for the QML.

## Plugin-author side

- **Settings as their own window.** Today a hub card shows its plugin's whole popup, including a plugin's settings, which expands the card's content inline (the arXiv scanner's Settings button does this). The aim is for a card's Settings to open its own window, like "Hub settings", leaving the card compact. *This comes after publication:* it needs changes on the `hub-integration` branch of the arXiv scanner and on the published `arxiv-scanner` repo's `main`, and the hub should be public and stable first, so that `main` never depends on an unpublished consumer. A likely shape is an optional card entry point (e.g. `settingsEntry`) in the contract, with the hub hosting that window.
- **Namespace or upstream the manifest key.** `hubCard` is this plugin's own convention. Either namespace it (e.g. `x-…`) or propose a first-class "card" capability to Omarchy so the shell can host it natively.
- **Let a card ask the hub to close.** The hub closes when another window becomes active, which covers links and notification actions in testing. If some setups (for example with focus-stealing prevention) do not activate the target window, an optional hook in the card contract would let a card's link handlers dismiss the hub explicitly.
- **Contract v2 ideas**: cards declaring a preferred or collapsed height, a "needs attention" state separate from a numeric badge, and an explicit refresh hook.
- **Convert more plugins**, using [MIGRATING.md](MIGRATING.md).
- **Take the `hub-integration` work live.** The card changes for the arXiv scanner (a `git worktree` of the published repo, checked out on `hub-integration` and symlinked in as the live plugin) and the football tracker (its own fork, `hub-integration` branch, with a local push guard) are unpublished. Once the hub is public and stable, merge them into each plugin's `main` — one plugin at a time, each as a non-breaking change — and remove the football push guard then. Nothing is pushed before that.

## Not planned

- Pulling an *unmodified* plugin popup out of its plugin into the hub. It would bypass the isolation Omarchy's plugin facades provide, break the plugin's own popup while the hub holds it, and depend on private internals.
