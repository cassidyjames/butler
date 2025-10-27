/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2024 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.MainWindow : Adw.ApplicationWindow {
    private const GLib.ActionEntry[] ACTION_ENTRIES = {
        { "toggle_fullscreen", toggle_fullscreen },
        { "settings", on_settings_activate },
        { "log_out", on_log_out_activate },
        { "about", on_about_activate },
    };

    private Adw.Banner demo_banner;
    private Adw.Toast fullscreen_toast;
    private Adw.ToastOverlay toast_overlay;
    private Gtk.Revealer header_revealer;
    private Gtk.Revealer home_revealer;
    private Adw.AboutDialog about_dialog;
    private Butler.WebView web_view;
    private Gtk.ColorDialogButton color_light_button;
    private Gtk.ColorDialogButton color_dark_button;

    private const string CSS = """
        @define-color headerbar_bg_light %s;
        @define-color headerbar_fg_light %s;

        @define-color headerbar_bg_dark %s;
        @define-color headerbar_fg_dark %s;
    """;
    private Gtk.CssProvider css_provider;

    public MainWindow (Adw.Application app) {
        Object (
            application: app,
            height_request: 294,
            icon_name: APP_ID,
            resizable: true,
            title: APP_NAME,
            width_request: 360
        );
        add_action_entries (ACTION_ENTRIES, this);
    }

    construct {
        maximized = App.settings.get_boolean ("window-maximized");
        fullscreened = App.settings.get_boolean ("window-fullscreened");
        add_css_class (PROFILE);

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

        var home_button = new Gtk.Button.from_icon_name ("go-home-symbolic") {
            tooltip_text = _("Go Home")
        };

        home_revealer = new Gtk.Revealer () {
            child = home_button,
            transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT
        };

        var site_menu = new Menu ();
        site_menu.append (_("_Log Out…"), "win.log_out");

        var app_menu = new Menu ();
        // TODO: How do I add shortcuts to the menu?
        app_menu.append (_("_Fullscreen"), "win.toggle_fullscreen");
        app_menu.append (_("_Settings"), "win.settings");
        app_menu.append (_("_About %s").printf (APP_NAME), "win.about");

        var menu = new Menu ();
        menu.append_section (null, site_menu);
        menu.append_section (null, app_menu);

        var menu_button = new Gtk.MenuButton () {
            icon_name = "open-menu-symbolic",
            menu_model = menu,
            tooltip_text = _("Main Menu"),
        };

        var header = new Adw.HeaderBar ();
        header.pack_start (home_revealer);
        header.pack_end (menu_button);

        header_revealer = new Gtk.Revealer () {
            child = header,
            reveal_child = !fullscreened
        };

        demo_banner = new Adw.Banner (_("Browsing Home Assistant Demo")) {
            action_name = "win.settings",
            button_label = _("Change _Server…")
        };

        fullscreen_toast = new Adw.Toast (_("Press <b>F11</b> to toggle fullscreen")) {
            action_name = "win.toggle_fullscreen",
            button_label = _("Exit _Fullscreen")
        };

        web_view = new Butler.WebView ();

        string server = App.settings.get_string ("server");
        string current_url = App.settings.get_string ("current-url");
        if (current_url != "") {
            web_view.load_uri (current_url);
        } else {
            web_view.load_uri (server);
        }

        var status_page = new Adw.StatusPage () {
            title = APP_NAME,
            description = _("Loading the dashboard…"),
            icon_name = APP_ID
        };

        var stack = new Gtk.Stack () {
            // Half speed since it's such a huge distance
            transition_duration = 400,
            transition_type = Gtk.StackTransitionType.UNDER_UP
        };
        stack.add_css_class ("loading");
        stack.add_named (status_page, "loading");
        stack.add_named (web_view, "web");

        string headerbar_color_light, headerbar_color_dark;
        App.settings.get ("headerbar-colors", "(ss)", out headerbar_color_light, out headerbar_color_dark);
        update_headerbar_colors (headerbar_color_light, headerbar_color_dark);

        toast_overlay = new Adw.ToastOverlay () {
            child = stack
        };

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        box.append (header_revealer);
        box.append (toast_overlay);
        box.append (demo_banner);

        set_content (box);

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
            if (load_event == WebKit.LoadEvent.FINISHED) {
                stack.visible_child_name = "web";
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
        Gtk.StyleContext.add_provider_for_display (
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
        string current_server = App.settings.get_string ("server");
        string default_server = App.settings.get_default_value ("server").get_string ();

        string current_color_light, current_color_dark;
        App.settings.get ("headerbar-colors", "(ss)", out current_color_light, out current_color_dark);

        var current_rgba_light = Gdk.RGBA ();
        current_rgba_light.parse (current_color_light);

        var current_rgba_dark = Gdk.RGBA ();
        current_rgba_dark.parse (current_color_dark);

        var server_reset_button = new Gtk.Button.from_icon_name ("step-back-symbolic") {
            tooltip_text = _("Reset to Demo"),
            valign = Gtk.Align.CENTER,
        };
        server_reset_button.add_css_class ("flat");

        var server_entry = new Adw.EntryRow () {
            activates_default = true,
            input_purpose = Gtk.InputPurpose.URL,
            show_apply_button = true,
            text = current_server,
            title = _("Server URL"),
        };
        server_entry.add_suffix (server_reset_button);

        var server_group = new Adw.PreferencesGroup () {
            title = _("Server"),
            description = _("Enter the full URL including any custom port"),
        };
        server_group.add (server_entry);

        color_light_button = new Gtk.ColorDialogButton (new Gtk.ColorDialog ()) {
            rgba = current_rgba_light,
            valign = Gtk.Align.CENTER,
        };

        var color_light_row = new Adw.ActionRow () {
            title = _("Light"),
            subtitle = _("Used with default system style preference"),
            activatable_widget = color_light_button,
        };
        color_light_row.add_suffix (color_light_button);

        color_dark_button = new Gtk.ColorDialogButton (new Gtk.ColorDialog ()) {
            rgba = current_rgba_dark,
            valign = Gtk.Align.CENTER,
        };

        var color_dark_row = new Adw.ActionRow () {
            title = _("Dark"),
            subtitle = _("Used with dark system style preference"),
            activatable_widget = color_dark_button,
        };
        color_dark_row.add_suffix (color_dark_button);

        var color_reset_button = new Gtk.Button.from_icon_name ("step-back-symbolic") {
            tooltip_text = _("Reset to Default"),
            valign = Gtk.Align.CENTER,
        };
        color_reset_button.add_css_class ("flat");

        var color_group = new Adw.PreferencesGroup () {
            title = _("Header Colors"),
            description = _("Better match your dashboard"),
        };
        color_group.add (color_light_row);
        color_group.add (color_dark_row);
        color_group.set_header_suffix (color_reset_button);

        var settings_page = new Adw.PreferencesPage ();
        settings_page.add (server_group);
        settings_page.add (color_group);

        var settings_dialog = new Adw.PreferencesDialog () {
            content_width = 480,
            title = _("Settings"),
        };
        settings_dialog.add (settings_page);

        settings_dialog.present (this);

        server_entry.apply.connect (() => {
            string new_server = server_entry.text.strip ();

            if (new_server == "") {
                new_server = default_server;
            }

            if (!new_server.contains ("://")) {
                new_server = "http://" + new_server;
            }

            if (new_server != current_server) {
                // FIXME: There's currently no validation of this
                App.settings.set_string ("server", new_server);
                log_out ();
            }
        });

        server_reset_button.clicked.connect (() => {
            server_entry.text = default_server;
            server_entry.apply ();
        });

        color_reset_button.clicked.connect (() => {
            string light, dark;

            App.settings.reset ("headerbar-colors");
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
    }

    private void on_color_button_change () {
        string light = color_light_button.get_rgba ().to_string ();
        string dark = color_dark_button.get_rgba ().to_string ();

        App.settings.set (
            "headerbar-colors", "(ss)", light, dark
        );

        update_headerbar_colors (light, dark);
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
