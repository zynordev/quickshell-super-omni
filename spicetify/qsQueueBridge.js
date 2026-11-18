(function qsQueueBridge() {
    if (!window.Spicetify || !Spicetify.addToQueue) {
        setTimeout(qsQueueBridge, 500);
        return;
    }
    setInterval(async () => {
        try {
            const resp = await fetch("http://127.0.0.1:29584/pop");
            if (!resp.ok) return;
            const items = await resp.json();
            if (Array.isArray(items) && items.length > 0) {
                for (const item of items) {
                    if (item && item.uri) {
                        await Spicetify.addToQueue([{ uri: item.uri }]);
                        if (Spicetify.showNotification && item.display) {
                            Spicetify.showNotification("➕ Sıraya eklendi: " + item.display);
                        }
                    }
                }
            }
        } catch (e) {
            // Daemon not running when queue is empty
        }
    }, 1500);
})();
