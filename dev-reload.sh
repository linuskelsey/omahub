#!/usr/bin/env bash
# The shell runs with QS_DISABLE_FILE_WATCHER=1, so QML edits only take effect
# after a deliberate restart.
exec omarchy restart shell
