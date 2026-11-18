pragma Singleton

import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

Singleton {
    id: root

    property string query: ""

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.symbols, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch,].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }
    
    Process {
        id: keywordHarvester
        property var pendingPages: []
        property string currentPageName: ""
        
        function startHarvesting() {
            root.settingsKeywordsCache = {}; 
            pendingPages = root.settingsIndex.slice();
            next();
        }

        function next() {
            if (pendingPages.length === 0) {
                return;
            }
            
            let currentPage = pendingPages.shift();
            let fullPath = FileUtils.trimFileProtocol(
                Quickshell.shellPath("modules/ii/settings/pages/" + currentPage.path)
            )

            let rawCommand = "grep -oP \"title:\\s*Translation.tr\\(['\\\"].*?['\\\"]\\)\" " + fullPath + " | sed -E \"s/title:\\s*Translation.tr\\(['\\\"](.*)['\\\"]\\)/\\1/g\" | tr '\\n' ' '";
            
            command = ["bash", "-c", rawCommand];
            
            keywordHarvester.currentPageName = currentPage.page;
            running = true;
        }

        onExited: (exitCode, exitStatus) => {
            keywordHarvester.next();
        }

        stdout: SplitParser {
            onRead: data => {
                let cache = root.settingsKeywordsCache;
                cache[keywordHarvester.currentPageName] = (cache[keywordHarvester.currentPageName] || "") + " " + data;
                root.settingsKeywordsCache = cache;
            }
        }
    }

    Component.onCompleted: {
        keywordHarvester.startHarvesting();
    }


    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    property var settingsKeywordsCache: ({})

    property var settingsIndex: [
        { page: "General",   path: "GeneralConfig.qml" },
        { page: "Bar",       path: "BarConfig.qml" },
        { page: "Desktop",   path: "BackgroundConfig.qml" },
        { page: "Interface", path: "InterfaceConfig.qml" },
        { page: "Services",  path: "ServicesConfig.qml" },
        { page: "Hyprland",  path: "HyprlandConfig.qml" },
        { page: "About",     path: "About.qml" },
        { page: "Quick",     path: "QuickConfig.qml" },
    ]

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`)
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Quickshell.execDetached(["bash", "-c", "rm -f ~/.cache/cliphist/db"]);
            }
        },
        {
            action: "unsplash",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("Usage: /unsplash YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "unsplash"], args.trim());
                Quickshell.execDetached(["notify-send", "Unsplash", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "wallhaven",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("Usage: /wallhaven YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "wallhaven"], args.trim());
                Quickshell.execDetached(["notify-send", "Wallhaven", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "pexels",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("Usage: /pexels YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "pexels"], args.trim());
                Quickshell.execDetached(["notify-send", "Pexels", Translation.tr("API key saved!"), "-a", "Shell"]);
            }
        },
        {
            action: "openweather",
            execute: args => {
                if (!args || args.trim().length === 0) {
                    Quickshell.execDetached(["notify-send", "OpenWeather", Translation.tr("Usage: /openweather YOUR_API_KEY"), "-a", "Shell"]);
                    return;
                }
                KeyringStorage.setNestedField(["apiKeys", "openweather"], args.trim());
                Quickshell.execDetached(["notify-send", "OpenWeather", Translation.tr("API key saved!"), "-a", "Shell"]);
                Weather.getData();
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property string helperScriptPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/super_menu_helper.py"))
    property var fileSearchResults: []
    property string lastFileQuery: ""
    property var spotifySearchResults: []
    property string lastSpotifyQuery: ""
    property var spotifyHistoryResults: []
    property string lastSpotifyHistoryQuery: ""
    property var smartSuggestions: []
    property string lastSuggestionQuery: ""

    onQueryChanged: {
        if (root.query.startsWith("/")) {
            fileSearchTimer.restart();
        } else if (/^[pqPQ](\s+.*)?$/.test(root.query)) {
            spotifyHistoryTimer.restart();
            const songQ = root.query.replace(/^[pqPQ]\s*/, "").trim();
            if (songQ.length > 0) {
                spotifySearchTimer.restart();
            }
        } else if (root.query.trim().length > 0) {
            suggestionTimer.restart();
        }
    }

    Timer {
        id: spotifyHistoryTimer
        interval: 20
        onTriggered: {
            if (/^[pqPQ](\s+.*)?$/.test(root.query)) {
                const isPlay = root.query[0].toLowerCase() === "p";
                const songQ = root.query.replace(/^[pqPQ]\s*/, "").trim();
                spotifyHistoryProc.search(isPlay, songQ);
            }
        }
    }

    Process {
        id: spotifyHistoryProc
        property string targetQuery: ""
        function search(isPlay, q) {
            spotifyHistoryProc.running = false;
            spotifyHistoryProc.targetQuery = q.toLowerCase();
            spotifyHistoryProc.command = ["python3", root.helperScriptPath, "spotify-history", isPlay ? "play" : "queue", q];
            spotifyHistoryProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.spotifyHistoryResults = JSON.parse(data);
                    root.lastSpotifyHistoryQuery = spotifyHistoryProc.targetQuery;
                } catch (e) {
                    root.spotifyHistoryResults = [];
                }
            }
        }
    }

    Timer {
        id: suggestionTimer
        interval: 35
        onTriggered: {
            const q = root.query.trim();
            if (q.length > 0 && !q.startsWith("/")) {
                suggestionProc.search(q);
            }
        }
    }

    Process {
        id: suggestionProc
        property string targetQuery: ""
        function search(q) {
            suggestionProc.running = false;
            suggestionProc.targetQuery = q.toLowerCase();
            suggestionProc.command = ["python3", root.helperScriptPath, "suggestions", q];
            suggestionProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.smartSuggestions = JSON.parse(data);
                    root.lastSuggestionQuery = suggestionProc.targetQuery;
                } catch (e) {
                    root.smartSuggestions = [];
                }
            }
        }
    }

    Timer {
        id: fileSearchTimer
        interval: 40
        onTriggered: {
            if (root.query.startsWith("/")) {
                fileSearchProc.search(root.query);
            }
        }
    }

    Process {
        id: fileSearchProc
        property string targetQuery: ""
        function search(q) {
            fileSearchProc.running = false;
            fileSearchProc.targetQuery = q;
            fileSearchProc.command = ["python3", root.helperScriptPath, "file-search", q];
            fileSearchProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.fileSearchResults = JSON.parse(data);
                    root.lastFileQuery = fileSearchProc.targetQuery;
                } catch (e) {
                    root.fileSearchResults = [];
                }
            }
        }
    }

    Timer {
        id: spotifySearchTimer
        interval: 180
        onTriggered: {
            if (/^[pqPQ]\s+.+/.test(root.query)) {
                const songQ = root.query.replace(/^[pqPQ]\s+/, "").trim();
                if (songQ.length > 0) {
                    spotifySearchProc.search(songQ);
                }
            }
        }
    }

    Process {
        id: spotifySearchProc
        property string targetSongQuery: ""
        function search(sq) {
            spotifySearchProc.running = false;
            spotifySearchProc.targetSongQuery = sq.toLowerCase();
            spotifySearchProc.command = ["python3", root.helperScriptPath, "spotify-search", sq];
            spotifySearchProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.spotifySearchResults = JSON.parse(data);
                    root.lastSpotifyQuery = spotifySearchProc.targetSongQuery;
                } catch (e) {
                    root.spotifySearchResults = [];
                }
            }
        }
    }

    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay
        onTriggered: {
            let expr = root.query;
            if (expr.startsWith(Config.options.search.prefix.math)) {
                expr = expr.slice(Config.options.search.prefix.math.length);
            }
            mathProc.calculateExpression(expr);
        }
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return [];

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            return Cliphist.fuzzyQuery(searchString).map((entry, index, array) => {
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })],
                    blurImage: shouldBlurImage
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Emojis
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, ""),
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                    }
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.keybinds ?? "<")) {
            // Keybinds
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.keybinds ?? "<");
            const flatBinds = (function flatten(node) {
                let result = [...(node.keybinds ?? [])];
                for (const child of (node.children ?? [])) {
                    result = result.concat(flatten(child));
                }
                return result;
            })(HyprlandKeybinds.keybinds);

            return flatBinds.filter(bind => {
                if (!bind.comment) return false;
                if (searchString.length === 0) return true;
                return bind.comment.toLowerCase().includes(searchString.toLowerCase())
                    || bind.key.toLowerCase().includes(searchString.toLowerCase());
            }).map(bind => {
                const modsStr = bind.mods.join(" + ");
                const keyStr  = modsStr.length > 0 ? `${modsStr} + ${bind.key}` : bind.key;
                return resultComp.createObject(null, {
                    name: bind.comment,
                    iconName: "keyboard",
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: keyStr,
                    type: Translation.tr("Keybind"),
                    comment: keyStr,
                    execute: () => {
                        Quickshell.clipboardText = keyStr;
                    }
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.symbols)) {
            // Material Symbols
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.symbols);
            return MaterialSymbolsSearch.fuzzyQuery(searchString).map(entry => {
                const tabIdx = entry.indexOf("\t");
                const symName = tabIdx >= 0 ? entry.slice(0, tabIdx) : entry;
                const symTags = tabIdx >= 0 ? entry.slice(tabIdx + 1) : "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: symName,
                    iconName: symName,
                    iconType: LauncherSearchResult.IconType.Material,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Symbol"),
                    comment: symTags,
                    execute: () => {
                        Quickshell.clipboardText = symName;
                    }
                });
            }).filter(Boolean);
        } else if (/^[pqPQ](\s+.*)?$/.test(root.query)) {
            // Spotify Play (p <song>) or Queue (q <song>)
            const isPlay = root.query[0].toLowerCase() === "p";
            const songQuery = root.query.replace(/^[pqPQ]\s*/, "").trim();

            let historyItems = [];
            if (root.lastSpotifyHistoryQuery === songQuery.toLowerCase() && root.spotifyHistoryResults.length > 0) {
                historyItems = root.spotifyHistoryResults.map(h => {
                    return resultComp.createObject(null, {
                        name: `${isPlay ? "p" : "q"} ${h.text}`,
                        comment: (isPlay ? "🎵 Geçmişte Çalındı" : "➕ Geçmişte Sıraya Eklendi") + " (" + (h.count || 1) + " kez)",
                        verb: isPlay ? "Oynat" : "Sıraya Ekle",
                        type: "Spotify Geçmişi",
                        iconName: "history",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            if (h.uri) {
                                Quickshell.execDetached(["python3", root.helperScriptPath, isPlay ? "spotify-play" : "spotify-queue", h.uri, h.text]);
                            } else {
                                Quickshell.execDetached(["python3", root.helperScriptPath, isPlay ? "spotify-play-query" : "spotify-queue-query", h.text]);
                            }
                        }
                    });
                });
            }

            if (songQuery.length === 0) {
                const promptItem = resultComp.createObject(null, {
                    name: isPlay ? "Spotify'da oynatmak için şarkı adı yazın..." : "Spotify sırasına eklemek için şarkı adı yazın...",
                    comment: isPlay ? "Örnek: p duman senden daha güzel" : "Örnek: q mor ve ötesi bir derdim var",
                    verb: isPlay ? "Oynat" : "Sıraya Ekle",
                    type: "Spotify",
                    iconName: isPlay ? "play_circle" : "queue_music",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {}
                });
                return historyItems.length > 0 ? historyItems.concat([promptItem]) : [promptItem];
            }

            const directItem = resultComp.createObject(null, {
                name: songQuery,
                comment: isPlay ? "🎵 Spotify'da Hemen Bul ve Oynat" : "➕ Spotify'da Bul ve Sıraya Ekle",
                verb: isPlay ? "Oynat" : "Sıraya Ekle",
                type: "Spotify",
                iconName: isPlay ? "play_circle" : "queue_music",
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => {
                    Quickshell.execDetached(["python3", root.helperScriptPath, isPlay ? "spotify-play-query" : "spotify-queue-query", songQuery]);
                }
            });

            if (root.lastSpotifyQuery === songQuery.toLowerCase() && root.spotifySearchResults.length > 0) {
                const trackItems = root.spotifySearchResults.map(track => {
                    return resultComp.createObject(null, {
                        name: track.display,
                        comment: (isPlay ? "🎵 Spotify'da Oynat" : "➕ Spotify Sırasına Ekle") + (track.album ? ` • ${track.album}` : ""),
                        verb: isPlay ? "Oynat" : "Sıraya Ekle",
                        type: "Spotify",
                        iconName: isPlay ? "play_circle" : "queue_music",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["python3", root.helperScriptPath, isPlay ? "spotify-play" : "spotify-queue", track.uri, track.display]);
                        },
                        actions: [
                            resultComp.createObject(null, {
                                name: isPlay ? "Sıraya Ekle" : "Şimdi Oynat",
                                iconName: isPlay ? "queue_music" : "play_arrow",
                                iconType: LauncherSearchResult.IconType.Material,
                                execute: () => {
                                    Quickshell.execDetached(["python3", root.helperScriptPath, isPlay ? "spotify-queue" : "spotify-play", track.uri, track.display]);
                                }
                            })
                        ]
                    });
                });
                return historyItems.concat(trackItems).concat([directItem]);
            }

            return historyItems.concat([directItem]);
        }

        ////////////////// Init ///////////////////
        nonAppResultsTimer.restart();
        const mathResultObject = resultComp.createObject(null, {
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => {
            return resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)
                        entry.execute();
                    else {
                        // Probably needs more proper escaping, but this will do for now
                        Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                    }
                },
                comment: entry.comment,
                runInTerminal: entry.runInTerminal,
                genericName: entry.genericName,
                keywords: entry.keywords,
                actions: entry.actions.map(action => {
                    return resultComp.createObject(null, {
                        name: action.name,
                        iconName: action.icon,
                        iconType: LauncherSearchResult.IconType.System,
                        execute: () => {
                            if (!action.runInTerminal)
                                action.execute();
                            else {
                                Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                            }
                        }
                    });
                })
            });
        });
        ////////////////// Settings search //////////////////
        const settingsQuery = root.query.toLowerCase().trim();

        const settingsResults = root.settingsIndex.reduce((acc, page) => {
            const dynamicKeywords = (root.settingsKeywordsCache[page.page] || "").toLowerCase();
            const query = root.query.toLowerCase().trim();
            if (query === "") return acc;

            if (page.page.toLowerCase().includes(query) || dynamicKeywords.includes(query)) {
                acc.push(resultComp.createObject(null, {
                    name: page.page,
                    comment: dynamicKeywords.includes(query) ? "Section: " + query : "Settings for " + page.page,
                    verb: Translation.tr("Go"),
                    type: Translation.tr("Settings"),
                    iconName: "settings",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        GlobalStates.settingsOpen = true;
                        Qt.callLater(() => {
                            GlobalStates.settingsPage = page.page + ":" + query;
                        });
                        root.query = "";
                    }
                }));
            }
            return acc;
        }, []);
        const commandResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                Quickshell.execDetached(["python3", root.helperScriptPath, "run-shell", root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
        const webSearchResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch),
            comment: "🌐 Varsayılan Tarayıcı ile Google'da Ara",
            verb: Translation.tr("Search"),
            type: Translation.tr("Web search"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let query = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.webSearch).trim();
                Quickshell.execDetached(["python3", root.helperScriptPath, "open-search", query]);
            }
        });
        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (actionString.startsWith(root.query) || root.query.startsWith(actionString)) {
                return resultComp.createObject(null, {
                    name: root.query.startsWith(actionString) ? root.query : actionString,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        action.execute(root.query.split(" ").slice(1).join(" "));
                    }
                });
            }
            return null;
        }).filter(Boolean);

        //////// File & Folder Search with "/" /////////
        if (root.query.startsWith("/")) {
            let fileItems = [];
            if (root.lastFileQuery === root.query && root.fileSearchResults.length > 0) {
                fileItems = root.fileSearchResults.map(item => {
                    return resultComp.createObject(null, {
                        name: item.path,
                        comment: item.comment,
                        verb: item.verb,
                        type: item.is_dir ? "Klasör" : "Dosya",
                        iconName: item.is_dir ? "folder" : "description",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["python3", root.helperScriptPath, "file-open", item.path]);
                        }
                    });
                });
            } else {
                fileItems = [resultComp.createObject(null, {
                    name: root.query,
                    comment: `📁 ${root.query} — Dolphin'de Aç`,
                    verb: "Aç",
                    type: "Klasör/Dosya",
                    iconName: "folder_open",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        Quickshell.execDetached(["python3", root.helperScriptPath, "file-open", root.query]);
                    }
                })];
            }

            const exactActionMatch = root.allActions.some(a => {
                const actStr = `${Config.options.search.prefix.action}${a.action}`;
                return root.query === actStr || root.query.startsWith(actStr + " ");
            });

            if (exactActionMatch) {
                return launcherActionObjects.concat(fileItems);
            }
            return fileItems.concat(launcherActionObjects);
        }

        //////// Direct domain / URL -> open in Default Browser /////////
        const trimmedQuery = root.query.trim();
        const hasScheme = /^https?:\/\//i.test(trimmedQuery);
        const domainMatch = /^(?:https?:\/\/)?(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+([a-z]{2,24})(?::\d+)?(?:[\/?#]\S*)?$/i.exec(trimmedQuery);
        const fileExtLike = ["txt", "md", "py", "js", "sh", "json", "pdf", "png", "jpg", "jpeg", "qml", "lua", "conf", "ini", "zip", "log", "csv", "yml", "yaml", "html", "css", "cpp", "java", "mp3", "mp4"];
        const isDomain = domainMatch !== null && (hasScheme || !fileExtLike.includes(domainMatch[1].toLowerCase()));
        let domainResultObject = null;
        if (isDomain) {
            const targetUrl = hasScheme ? trimmedQuery : "https://" + trimmedQuery;
            domainResultObject = resultComp.createObject(null, {
                name: trimmedQuery,
                comment: "🌐 Tarayıcıda doğrudan aç",
                verb: Translation.tr("Open"),
                type: "Web sitesi",
                iconName: 'language',
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => {
                    Quickshell.execDetached(["python3", root.helperScriptPath, "open-url", targetUrl]);
                }
            });
        }

        //////// Prioritized by prefix /////////
        let result = [];
        if (domainResultObject)
            result.push(domainResultObject);

        //////// Smart Suggestions (Browser History + Launcher History: songs, sites, searches, commands) /////////
        if (root.lastSuggestionQuery === trimmedQuery.toLowerCase() && root.smartSuggestions.length > 0) {
            for (let i = 0; i < root.smartSuggestions.length; i++) {
                const s = root.smartSuggestions[i];
                if (s.type === "zen_url" || s.type === "browser_url" || s.type === "url") {
                    result.push(resultComp.createObject(null, {
                        name: s.text,
                        comment: (s.data ? `${s.data} • ` : "") + "🌐 Tarayıcı Geçmişi (" + (s.count || 1) + " ziyaret)",
                        verb: "Aç",
                        type: "Web sitesi",
                        iconName: "history",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["python3", root.helperScriptPath, "open-url", s.text]);
                        }
                    }));
                } else if (s.type === "spotify_play") {
                    result.push(resultComp.createObject(null, {
                        name: `p ${s.text}`,
                        comment: `🎵 Geçmiş Şarkı: ${s.text} (${s.count || 1} kez çalındı)`,
                        verb: "Oynat",
                        type: "Spotify",
                        iconName: "play_circle",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            if (s.data) {
                                Quickshell.execDetached(["python3", root.helperScriptPath, "spotify-play", s.data, s.text]);
                            } else {
                                Quickshell.execDetached(["python3", root.helperScriptPath, "spotify-play-query", s.text]);
                            }
                        }
                    }));
                } else if (s.type === "spotify_queue") {
                    result.push(resultComp.createObject(null, {
                        name: `q ${s.text}`,
                        comment: `➕ Geçmiş Şarkı: ${s.text} (${s.count || 1} kez sıraya eklendi)`,
                        verb: "Sıraya Ekle",
                        type: "Spotify",
                        iconName: "queue_music",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            if (s.data) {
                                Quickshell.execDetached(["python3", root.helperScriptPath, "spotify-queue", s.data, s.text]);
                            } else {
                                Quickshell.execDetached(["python3", root.helperScriptPath, "spotify-queue-query", s.text]);
                            }
                        }
                    }));
                } else if (s.type === "search") {
                    result.push(resultComp.createObject(null, {
                        name: s.text,
                        comment: `🔍 Geçmiş Arama: "${s.text}" (${s.count || 1} kez arandı)`,
                        verb: "Ara",
                        type: "Web search",
                        iconName: "search",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["python3", root.helperScriptPath, "open-zen-search", s.text]);
                        }
                    }));
                } else if (s.type === "command") {
                    result.push(resultComp.createObject(null, {
                        name: s.text,
                        comment: `⚡ Geçmiş Komut: \`${s.text}\` (${s.count || 1} kez çalıştırıldı)`,
                        verb: "Çalıştır",
                        type: "Command",
                        fontType: LauncherSearchResult.FontType.Monospace,
                        iconName: "terminal",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["python3", root.helperScriptPath, "run-shell", s.text]);
                        }
                    }));
                }
            }
        }
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
        }

        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);
        ////////////// Settings ////////////////
        result = result.concat(settingsResults);
        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        /// Web search (Zen Browser), command, math result ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithWebSearchPrefix)
                result.push(webSearchResultObject);
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix)
                result.push(mathResultObject);
        }
        
        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
