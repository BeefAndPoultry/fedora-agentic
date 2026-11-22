// KWin bridge for Fedora Agentic (issue #49, Phase 1 — KWin side only).
//
// Runs inside the KWin scripting environment. It serialises window state via
// the `workspace` API and pushes snapshots to the desktop-mcp Rust daemon over
// session D-Bus, while polling that daemon for pending window actions to run.
//
// NOTE: this script is inert until two things are true:
//   1. it is installed + enabled (see /usr/local/libexec/install-kwin-bridge.sh), and
//   2. the desktop-mcp daemon owns the org.fedora.Agentic.KWin D-Bus service.
// Until the daemon exists every callDBus() is wrapped in try/catch below so a
// missing peer merely logs to stderr instead of spamming KWin's log every 100 ms.

const DBUS_SERVICE = "org.fedora.Agentic.KWin";
const DBUS_PATH = "/org/fedora/Agentic/KWin";
const DBUS_IFACE = "org.fedora.Agentic.KWin";

function serializeWindow(win) {
    if (!win) return null;

    // Combine pid and internalId for a stable unique identifier so the agent
    // never acts on a window that has since changed identity or closed.
    const stableId = `${win.pid}-${win.internalId}`;

    // desktop number: -1 means "all desktops" in KWin.
    let desktop = -1;
    if (win.desktops && win.desktops.length > 0) {
        desktop = win.desktops[0].x11DesktopNumber;
    }

    return {
        id: stableId,
        title: win.caption || "",
        app_id: win.resourceClass || "",
        desktop: desktop,
        geometry: {
            x: Math.round(win.frameGeometry.x),
            y: Math.round(win.frameGeometry.y),
            width: Math.round(win.frameGeometry.width),
            height: Math.round(win.frameGeometry.height)
        }
    };
}

// Push a state snapshot to the daemon. Never throws: if the daemon is not
// running (Phase 1 ships this script before the Rust daemon) we log once and
// keep going instead of flooding KWin's log.
function pushState(payload) {
    try {
        callDBus(
            DBUS_SERVICE,
            DBUS_PATH,
            DBUS_IFACE,
            "UpdateState",
            payload
        );
    } catch (e) {
        print("kwin-bridge: daemon unreachable, skipping state push (" + e + ")");
    }
}

function syncStateToDaemon() {
    let windows = [];
    try {
        windows = workspace.windowList()
            // Exclude panels, tooltips and the desktop background.
            .filter(function (w) { return w.normalWindow; })
            .map(serializeWindow);
    } catch (e) {
        print("kwin-bridge: windowList failed (" + e + ")");
    }

    let active = null;
    try {
        active = workspace.activeWindow ? serializeWindow(workspace.activeWindow) : null;
    } catch (e) {
        print("kwin-bridge: activeWindow read failed (" + e + ")");
    }

    pushState(JSON.stringify({ windows: windows, active: active }));
}

function executeAction(actionJson) {
    if (!actionJson) return;
    let cmd;
    try {
        cmd = JSON.parse(actionJson);
    } catch (e) {
        print("kwin-bridge: ignoring malformed command " + actionJson);
        return;
    }
    if (!cmd || typeof cmd.window_id === "undefined") return;

    let target = null;
    try {
        target = workspace.windowList().find(function (w) {
            return (w.pid + "-" + w.internalId) === cmd.window_id;
        });
    } catch (e) {
        print("kwin-bridge: window lookup failed (" + e + ")");
    }
    if (!target) {
        print("kwin-bridge: no window matching id " + cmd.window_id);
        return;
    }

    try {
        switch (cmd.action) {
            case "focus":
                workspace.activeWindow = target;
                break;
            case "move":
                target.frameGeometry = {
                    x: cmd.x,
                    y: cmd.y,
                    width: target.frameGeometry.width,
                    height: target.frameGeometry.height
                };
                break;
            case "minimize":
                target.minimized = true;
                break;
            case "maximize":
                target.setMaximize(true, true);
                break;
            default:
                print("kwin-bridge: unknown action '" + cmd.action + "'");
        }
    } catch (e) {
        print("kwin-bridge: action '" + cmd.action + "' failed (" + e + ")");
    }

    syncStateToDaemon();
}

// Poll the daemon for queued actions. A 100 ms poll is deliberately kept as the
// Phase 1 default; a future version can switch to D-Bus event-driven signals
// once desktop-mcp emits them (issue #49 open question).
const timer = new QTimer();
timer.interval = 100;
timer.timeout.connect(function () {
    try {
        callDBus(DBUS_SERVICE, DBUS_PATH, DBUS_IFACE, "PopCommand", executeAction);
    } catch (e) {
        // daemon not running yet — ignore until it is.
    }
});
timer.start();

// Hook workspace signals for real-time state updates.
try {
    workspace.windowAdded.connect(syncStateToDaemon);
    workspace.windowRemoved.connect(syncStateToDaemon);
    workspace.windowActivated.connect(syncStateToDaemon);
} catch (e) {
    print("kwin-bridge: signal hooking failed (" + e + ")");
}

syncStateToDaemon();
