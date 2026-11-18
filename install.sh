#!/usr/bin/env bash
set -e

DEST_DIR="$HOME/.config/quickshell/end4-pC"
SPICETIFY_EXT_DIR="$HOME/.config/spicetify/Extensions"

echo "==> Installing quickshell-super-omni into $DEST_DIR..."

mkdir -p "$DEST_DIR/scripts/ai"
mkdir -p "$DEST_DIR/services/ai"
mkdir -p "$DEST_DIR/modules/ii/overview"
mkdir -p "$DEST_DIR/modules/ii/sidebarLeft/aiChat"
mkdir -p "$SPICETIFY_EXT_DIR"

cp scripts/super_menu_helper.py "$DEST_DIR/scripts/super_menu_helper.py"
chmod +x "$DEST_DIR/scripts/super_menu_helper.py"

cp scripts/ai/agy_runner.py "$DEST_DIR/scripts/ai/agy_runner.py"
chmod +x "$DEST_DIR/scripts/ai/agy_runner.py"

cp services/LauncherSearch.qml "$DEST_DIR/services/LauncherSearch.qml"
cp services/Ai.qml "$DEST_DIR/services/Ai.qml"
cp services/ai/AgyApiStrategy.qml "$DEST_DIR/services/ai/AgyApiStrategy.qml"

cp modules/overview/SearchBar.qml "$DEST_DIR/modules/ii/overview/SearchBar.qml"
cp modules/sidebarLeft/AiChat.qml "$DEST_DIR/modules/ii/sidebarLeft/AiChat.qml"
cp modules/sidebarLeft/aiChat/AiMessage.qml "$DEST_DIR/modules/ii/sidebarLeft/aiChat/AiMessage.qml"

cp spicetify/qsQueueBridge.js "$SPICETIFY_EXT_DIR/qsQueueBridge.js"

echo "==> Reloading Quickshell IPC..."
if command -v qs &>/dev/null; then
    qs -c end4-pC ipc call TEST_ALIVE || true
fi

echo "==> Done! Press Super to test your omni-launcher."
