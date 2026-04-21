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

        set_accels_for_action ("app.quit", {"<Ctrl>Q"});
        set_accels_for_action ("win.zoom-in", {"<Ctrl>plus", "<Ctrl>equal"});
        set_accels_for_action ("win.zoom-default", {"<Ctrl>0"});
        set_accels_for_action ("win.zoom-out", {"<Ctrl>minus"});
        set_accels_for_action ("win.reload", {"<Ctrl>R"});
        set_accels_for_action ("win.toggle_fullscreen", {"F11"});
        set_accels_for_action ("win.settings", {"<Ctrl>comma"});
    }

    public static int main (string[] args) {
        var app = new App ();
        return app.run (args);
    }
}
