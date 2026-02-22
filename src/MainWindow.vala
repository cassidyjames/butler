/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2026 Cassidy James Blaede <c@ssidyjam.es>
 */

[GtkTemplate (ui = "/com/cassidyjames/butler/ui/main-window.ui")]
public class Butler.MainWindow : Adw.ApplicationWindow {
    // gtk_style_context_add_provider_for_display has no non-deprecated Vala
    // binding; the GtkStyleContext class was deprecated in 4.10 but this C
    // function remains the correct way to add a global CSS provider.
    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    private extern static void add_css_provider_for_display (Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    private const GLib.ActionEntry[] ACTION_ENTRIES = {
        { "toggle_fullscreen", toggle_fullscreen },
        { "settings", on_settings_activate },
        { "log_out", on_log_out_activate },
        { "about", on_about_activate },
    };

    [GtkChild] private unowned Gtk.Revealer header_revealer;
    [GtkChild] private unowned Gtk.Revealer home_revealer;
    [GtkChild] private unowned Gtk.Button home_button;
    [GtkChild] private unowned Adw.Toast fullscreen_toast;
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Adw.Banner demo_banner;
    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Adw.StatusPage loading_page;
    [GtkChild] private unowned Adw.StatusPage error_page;
    [GtkChild] private unowned Gtk.Button error_retry_button;

    private Adw.AboutDialog about_dialog;
    private Butler.WebView web_view;
    private string? last_failed_uri = null;

    private const string CSS = """
        :root {
          --headerbar-bg-light: %s;
          --headerbar-fg-light: %s;

          --headerbar-bg-dark: %s;
          --headerbar-fg-dark: %s;
        }
    """;
    private Gtk.CssProvider css_provider;

    public MainWindow (Adw.Application app) {
        Object (application: app);
        add_action_entries (ACTION_ENTRIES, this);
    }

    construct {
        maximized = App.settings.get_boolean ("window-maximized");
        fullscreened = App.settings.get_boolean ("window-fullscreened");
        add_css_class (PROFILE);

        if (App.settings.get_boolean ("expressive-styling")) {
            add_css_class ("expressive");
        }
        App.settings.changed["expressive-styling"].connect (() => {
            if (App.settings.get_boolean ("expressive-styling")) {
                add_css_class ("expressive");
            } else {
                remove_css_class ("expressive");
            }
        });

        title = APP_NAME;
        icon_name = APP_ID;

        header_revealer.reveal_child = !fullscreened;

        loading_page.title = APP_NAME;
        loading_page.description = _("Loading the dashboard…");
        loading_page.icon_name = APP_ID;

        error_page.icon_name = APP_ID;

        about_dialog = new Adw.AboutDialog.from_appdata (
            "/com/cassidyjames/butler/metainfo.xml.in", VERSION
        ) {
            comments = _("Companion app to access your Home Assistant dashboard"),

            /// The translator credits. Please translate this with your name(s).
            translator_credits = _("translator-credits"),
            artists = {
                "Jakub Steiner https://jimmac.eu/",
                "Tobias Bernard https://tobiasbernard.com/",
            },
        };
        about_dialog.application_icon = APP_ID;
        about_dialog.application_name = APP_NAME;
        about_dialog.copyright = "© 2020–2024 %s".printf (
            about_dialog.developer_name
        );
        about_dialog.add_link (_("About Home Assistant"), "https://www.home-assistant.io/");
        about_dialog.add_link (_("Home Assistant Privacy Policy"), "https://www.home-assistant.io/privacy/");

        web_view = new Butler.WebView ();

        string server = App.settings.get_string ("server");
        string current_url = App.settings.get_string ("current-url");
        if (current_url != "") {
            web_view.load_uri (current_url);
        } else {
            web_view.load_uri (server);
        }

        stack.add_named (web_view, "web");

        string headerbar_color_light, headerbar_color_dark;
        App.settings.get ("headerbar-colors", "(ss)", out headerbar_color_light, out headerbar_color_dark);
        update_headerbar_colors (headerbar_color_light, headerbar_color_dark);

        int window_width, window_height;
        App.settings.get ("window-size", "(ii)", out window_width, out window_height);

        set_default_size (window_width, window_height);

        home_button.clicked.connect (() => {
            web_view.load_uri (server);
        });

        close_request.connect (() => {
            save_window_state ();
            return Gdk.EVENT_PROPAGATE;
        });
        notify["fullscreened"].connect (save_window_state);
        notify["maximized"].connect (save_window_state);

        web_view.load_changed.connect ((load_event) => {
            if (load_event == WebKit.LoadEvent.STARTED) {
                last_failed_uri = null;
                if (stack.visible_child_name == "error") {
                    stack.visible_child_name = "loading";
                }
            } else if (load_event == WebKit.LoadEvent.FINISHED && last_failed_uri == null) {
                stack.visible_child_name = "web";
            }
        });

        web_view.load_failed.connect ((load_event, failing_uri, error) => {
            last_failed_uri = failing_uri;
            error_page.description = error.message;
            demo_banner.revealed = false;
            stack.visible_child_name = "error";
            return true;
        });

        error_retry_button.clicked.connect (() => {
            if (last_failed_uri != null) {
                web_view.load_uri (last_failed_uri);
            }
        });

        web_view.load_changed.connect (on_loading);
        web_view.notify["uri"].connect (on_loading);
        web_view.notify["estimated-load-progress"].connect (on_loading);
        web_view.notify["is-loading"].connect (on_loading);

        App.settings.bind ("zoom", web_view, "zoom-level", SettingsBindFlags.DEFAULT);
    }

    private void update_headerbar_colors (string light, string dark) {
        var light_rgba = Gdk.RGBA ();
        light_rgba.parse (light);

        var dark_rgba = Gdk.RGBA ();
        dark_rgba.parse (dark);

        css_provider = new Gtk.CssProvider ();

        var css = CSS.printf (
            light_rgba.to_string (),
            contrasting_foreground_color (light_rgba).to_string (),
            dark_rgba.to_string (),
            contrasting_foreground_color (dark_rgba).to_string ()
        );

        css_provider.load_from_string (css);
        add_css_provider_for_display (
            Gdk.Display.get_default (),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
        );
    }

    private void save_window_state () {
        if (fullscreened) {
            App.settings.set_boolean ("window-fullscreened", true);
        } else if (maximized) {
            App.settings.set_boolean ("window-maximized", true);
        } else {
            App.settings.set_boolean ("window-fullscreened", false);
            App.settings.set_boolean ("window-maximized", false);
            App.settings.set (
                "window-size", "(ii)",
                get_size (Gtk.Orientation.HORIZONTAL),
                get_size (Gtk.Orientation.VERTICAL)
            );
        }
    }

    private void on_loading () {
        if (web_view.is_loading) {
            // TODO: Add a loading progress bar or spinner somewhere?
        } else if (last_failed_uri != null) {
            demo_banner.revealed = false;
        } else {
            string default_server = App.settings.get_default_value ("server").get_string ();
            string server = App.settings.get_string ("server");
            string current_url = web_view.uri;

            App.settings.set_string ("current-url", current_url);

            if (current_url.has_prefix (default_server)) {
                demo_banner.revealed = true;
            } else if (current_url.has_prefix (server)) {
                demo_banner.revealed = false;
            } else {
                // Somehow you got away from the server without opening a link
                // in the browser…
                demo_banner.revealed = false;
                home_revealer.set_reveal_child (true);
            }
        }
    }

    public void zoom_in () {
        if (web_view.zoom_level < 5.0) {
            web_view.zoom_level = web_view.zoom_level + 0.1;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already max");
        }

        return;
    }

    public void zoom_out () {
        if (web_view.zoom_level > 0.2) {
            web_view.zoom_level = web_view.zoom_level - 0.1;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already min");
        }

        return;
    }

    public void zoom_default () {
        if (web_view.zoom_level != 1.0) {
            web_view.zoom_level = 1.0;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already default");
        }

        return;
    }

    private void log_out () {
        web_view.network_session.get_website_data_manager ().clear.begin (
            WebKit.WebsiteDataTypes.ALL, 0, null, () => {
                debug ("Cleared data; going home.");
                web_view.load_uri (App.settings.get_string ("server"));
            }
        );
    }

    public void toggle_fullscreen () {
        if (fullscreened) {
            unfullscreen ();
            header_revealer.set_reveal_child (true);
            fullscreen_toast.dismiss ();
        } else {
            fullscreen ();
            header_revealer.set_reveal_child (false);
            toast_overlay.add_toast (fullscreen_toast);
        }
    }

    private void on_settings_activate () {
        var settings_dialog = new Butler.SettingsDialog ();
        settings_dialog.server_changed.connect (log_out);
        settings_dialog.colors_changed.connect (update_headerbar_colors);
        settings_dialog.present (this);
    }

    private void on_log_out_activate () {
        string server = App.settings.get_string ("server");

        var log_out_dialog = new Adw.AlertDialog (
            _("Log out of Home Assistant?"),
            _("You will need to re-enter any username and password required to log back in to <b>%s</b>.").printf (server)
        ) {
            body_use_markup = true,
            default_response = "log_out",
            prefer_wide_layout = true,
        };
        log_out_dialog.add_response ("close", _("_Stay Logged In"));
        log_out_dialog.add_response ("log_out", _("_Log Out"));
        log_out_dialog.set_response_appearance ("log_out", Adw.ResponseAppearance.DESTRUCTIVE);

        log_out_dialog.present (this);

        log_out_dialog.response.connect ((response_id) => {
            if (response_id == "log_out") {
                log_out ();
            }
        });
    }

    private void on_about_activate () {
        about_dialog.present (this);
    }
}
