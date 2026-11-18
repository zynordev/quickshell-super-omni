# quickshell-super-omni

> **Supercharge Hyprland's Quickshell with an Omni-Search launcher and native AI integration.**
> 
> Direct Dolphin file jumping, zero-click Spotify search & playback (MPRIS/GraphQL/Queue), Zen Browser direct domain opening, live history autocomplete, and local **Antigravity CLI (`agy`)** multi-agent integration.

---

## 🌟 Features

### 1. 📁 Deep File & Directory Navigation (Dolphin)
- Type `/home`, `/tmp`, `/Documents`, `/Downloads` or any path to jump directly into **Dolphin**.
- Instant search for files across your drive using `fd`.
- If a target is a directory, Dolphin opens the folder. If it is a file, Dolphin opens the containing folder with the file highlighted (`--select`).
- Preserves all built-in quickshell actions (`/dark`, `/light`, `/wallpaper`, `/todo`).

### 2. 🎵 Spotify Zero-Click Play & Queue (GraphQL + MPRIS)
- **`p <song>`:** Instant search via Spotify's internal Pathfinder GraphQL API and immediate playback through MPRIS D-Bus (`OpenUri`).
- **`q <song>`:** Add tracks directly to the playback queue without interrupting current music (via local Spicetify bridge extension and queue daemon).
- **`p` (empty):** Instant history of recently played tracks right at the top of the launcher.

### 3. 🌐 Dynamic Default Browser Launcher & Autocomplete
- Direct domain inputs (e.g. `bilgicoderteam.tr`, `github.com/zynordev`) bypass search engines and open immediately in your system's **default web browser** (dynamically detected via `xdg-settings` / desktop associations: Zen Browser, Firefox, Chrome, Brave, etc.).
- General search queries fallback to web search using your default browser.
- **Universal Browser History Autocomplete:** Reads places databases (`places.sqlite`) across modern browsers (Zen, Firefox, Librewolf, Waterfox) in immutable mode. Typing any keyword (e.g. `git`, `chat`) instantly presents your most visited websites and page titles.

### 4. 🧠 Unified Launcher Activity History
- Remembers past Spotify queries, shell commands, web searches, and opened URLs in `~/.cache/qs_launcher_history.json`.
- Displays usage count and auto-suggests past actions as you type.

### 5. 🤖 Native Antigravity (`agy`) Multi-Agent Sidebar
- Replaces generic cloud LLM APIs with your host's local **Antigravity CLI (`agy`)**.
- Access models directly without per-request API keys:
  - `gemini-4-argon-medium` / `high` / `low`
  - `gemini-4-hydrogen-high` / `xhigh` / `medium` / `low`
  - `claude-opus-5-5-high` / `medium` / `low`
  - `claude-sonnet-5-5-high` / `medium` / `low`
  - `gpt-oss-120b-medium`
- Real-time agent tool tracking (`run_command`, `read_file`, `web_search`) visible in collapsible `<think>` blocks.
- Multi-turn conversation persistence (`--conversation`).

---

## 📂 Project Structure

```text
quickshell-super-omni/
├── scripts/
│   ├── super_menu_helper.py    # Core engine: Dolphin, Spotify GraphQL/MPRIS, Zen history & cache
│   └── ai/
│       └── agy_runner.py       # agy CLI stream-json runner & conversation manager
├── services/
│   ├── LauncherSearch.qml      # Main launcher search orchestration & result models
│   ├── Ai.qml                  # AI singleton supporting the custom agy API strategy
│   └── ai/
│       └── AgyApiStrategy.qml  # QML strategy handling stream-json events & tool execution
├── modules/
│   ├── overview/
│   │   └── SearchBar.qml       # Search bar UI with dynamic prefix icons
│   └── sidebarLeft/
│       ├── AiChat.qml          # AI chat interface & model switcher
│       └── aiChat/
│           └── AiMessage.qml   # Message renderer with tool/think blocks
├── spicetify/
│   └── qsQueueBridge.js        # Spicetify extension polling local queue daemon
└── install.sh                  # Interactive installer and symlinker
```

---

## 🚀 Installation

### Prerequisites
- **Hyprland** with **Quickshell** (e.g. `end4-pC` / `illogical-impulse` dots)
- `python3`, `fd`, `playerctl`
- **Spotify** (optional: Spicetify for native queue bridge)
- **Zen Browser** (or edit browser path in `super_menu_helper.py`)
- **Antigravity CLI (`agy`)** for AI features

### Install Script
```bash
git clone https://github.com/zynordev/quickshell-super-omni.git
cd quickshell-super-omni
chmod +x install.sh
./install.sh
```

---

## 📜 License
MIT License. Created by [Halil Erdem Yanık (zynordev)](https://github.com/zynordev).
