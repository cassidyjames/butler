/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2026 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.App : Adw.Application {
    public static GLib.Settings settings;

    public App () {
        Object (application_id: APP_ID);
    }

    static construct {
        settings = new Settings (APP_ID);
    }

    protected override void activate () {
        if (active_window != null) {
            active_window.present ();
            return;
        }

        var app_window = new MainWindow (this);
        app_window.present ();

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (quit);
        add_action (quit_action);

        var restart_action = new SimpleAction ("restart", null);
        restart_action.activate.connect (restart);
        add_action (restart_action);

        set_accels_for_action ("app.quit", {"<Ctrl>Q"});
        set_accels_for_action ("win.zoom-in", {"<Ctrl>plus", "<Ctrl>equal"});
        set_accels_for_action ("win.zoom-default", {"<Ctrl>0"});
        set_accels_for_action ("win.zoom-out", {"<Ctrl>minus"});
        set_accels_for_action ("win.reload", {"<Ctrl>R"});
        set_accels_for_action ("win.toggle_fullscreen", {"F11"});
        set_accels_for_action ("win.settings", {"<Ctrl>comma"});
    }

    private void restart () {
        try {
            // Flatpak kills every process once the first one exits, so use
            // `flatpak-spawn` to launch a new instance of the app instead.
            if (Environment.get_variable ("FLATPAK_ID") != null) {
                Process.spawn_async (null,
                    { "flatpak-spawn", "--host", "flatpak", "run", APP_ID },
                    null, SpawnFlags.SEARCH_PATH, null, null
                );
            } else {
                Process.spawn_async (null,
                    { "/proc/self/exe" },
                    null, 0, null, null
                );
            }
        } catch (SpawnError e) {
            warning ("Unable to restart Butler: %s", e.message);
            return;
        }

        quit ();
    }

    public static int main (string[] args) {
        var app = new App ();
        return app.run (args);
    }
}
