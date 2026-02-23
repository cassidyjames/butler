/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2026 Cassidy James Blaede <c@ssidyjam.es>
 */

[GtkTemplate (ui = "/com/cassidyjames/butler/ui/settings-dialog.ui")]
public class Butler.SettingsDialog : Adw.PreferencesDialog {
    [GtkChild] private unowned Adw.EntryRow server_entry;
    [GtkChild] private unowned Gtk.Button server_reset_button;
    [GtkChild] private unowned Gtk.ColorDialogButton color_light_button;
    [GtkChild] private unowned Gtk.ColorDialogButton color_dark_button;
    [GtkChild] private unowned Gtk.Button color_reset_button;
    [GtkChild] private unowned Adw.SwitchRow expressive_row;

    public signal void server_changed ();
    public signal void colors_changed (string light, string dark);

    construct {
        string current_server = App.settings.get_string ("server");
        string default_server = App.settings.get_default_value ("server").get_string ();

        string current_color_light, current_color_dark;
        App.settings.get ("headerbar-colors", "(ss)", out current_color_light, out current_color_dark);

        var current_rgba_light = Gdk.RGBA ();
        current_rgba_light.parse (current_color_light);

        var current_rgba_dark = Gdk.RGBA ();
        current_rgba_dark.parse (current_color_dark);

        server_entry.text = current_server;
        color_light_button.rgba = current_rgba_light;
        color_dark_button.rgba = current_rgba_dark;

        server_entry.apply.connect (() => {
            string new_server = server_entry.text.strip ();

            if (new_server == "") {
                new_server = default_server;
            }

            if (!new_server.contains ("://")) {
                new_server = "http://" + new_server;
            }

            if (new_server != current_server) {
                App.settings.set_string ("server", new_server);
                App.settings.set_string ("current-url", new_server);
                server_changed ();
            }
        });

        server_reset_button.clicked.connect (() => {
            server_entry.text = default_server;
            server_entry.apply ();
        });

        color_reset_button.clicked.connect (() => {
            string light, dark;

            App.settings.reset ("headerbar-colors");
            App.settings.reset ("expressive-styling");
            App.settings.get ("headerbar-colors", "(ss)", out light, out dark);

            var light_rgba = Gdk.RGBA ();
            light_rgba.parse (light);

            var dark_rgba = Gdk.RGBA ();
            dark_rgba.parse (dark);

            color_light_button.rgba = light_rgba;
            color_dark_button.rgba = dark_rgba;
        });

        color_light_button.notify["rgba"].connect (on_color_button_change);
        color_dark_button.notify["rgba"].connect (on_color_button_change);

        App.settings.bind ("expressive-styling", expressive_row, "active", SettingsBindFlags.DEFAULT);
    }

    private void on_color_button_change () {
        string light = color_light_button.get_rgba ().to_string ();
        string dark = color_dark_button.get_rgba ().to_string ();

        App.settings.set (
            "headerbar-colors", "(ss)", light, dark
        );

        colors_changed (light, dark);
    }
}
