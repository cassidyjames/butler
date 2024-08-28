/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2024 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.MainWindow : Adw.ApplicationWindow {
    public Adw.AboutDialog about_dialog;
    public Adw.Banner demo_banner;
    public Adw.Toast fullscreen_toast;
    public Adw.ToastOverlay toast_overlay;
    public Gtk.Revealer header_revealer;
    public Gtk.Revealer home_revealer;

    private const GLib.ActionEntry[] ACTION_ENTRIES = {
        { "toggle_fullscreen", toggle_fullscreen },
        { "settings", on_settings_activate },
        { "log_out", on_log_out_activate },
        { "about", on_about_activate },
    };

    private Butler.WebView web_view;

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
        app_menu.append (_("_Server Settings"), "win.settings");
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

        fullscreen_toast = new Adw.Toast (_("Press <b>Ctrl F</b> or <b>F11</b> to toggle fullscreen")) {
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
            title = title,
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
                // NOTE: As of WebKitGTK in the GNOME 46 SDK, this seems
                // glitchier… not sure how to fix it. A GLib.Timeout doesn't
                // seem to help, as it just looks glitchy after the stack child
                // changes to the WebView.
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
        // Home Assistant doesn't use cookies for login; clear ALL to include
        // local storage and cache
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

        var server_entry = new Adw.EntryRow () {
            activates_default = true,
            text = current_server,
            title = _("Server URL"),
        };

        var server_group = new Adw.PreferencesGroup () {
            title = _("Server Settings"),
            description = _("Enter the full URL including any custom port"),
        };
        server_group.add (server_entry);

        var color_light_button = new Gtk.ColorDialogButton (new Gtk.ColorDialog ()) {
            rgba = current_rgba_light,
            valign = Gtk.Align.CENTER,
        };

        var color_light_row = new Adw.ActionRow () {
            title = _("Light"),
            subtitle = _("Used with default system style preference"),
            activatable_widget = color_light_button,
        };
        color_light_row.add_suffix (color_light_button);

        var color_dark_button = new Gtk.ColorDialogButton (new Gtk.ColorDialog ()) {
            rgba = current_rgba_dark,
            valign = Gtk.Align.CENTER,
        };

        var color_dark_row = new Adw.ActionRow () {
            title = _("Dark"),
            subtitle = _("Used with dark system style preference"),
            activatable_widget = color_dark_button,
        };
        color_dark_row.add_suffix (color_dark_button);

        var colors_group = new Adw.PreferencesGroup () {
            title = _("Header Bar Color"),
            description = _("Better match your dashboard"),
        };
        colors_group.add (color_light_row);
        colors_group.add (color_dark_row);

        var settings_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 24);
        settings_box.append (server_group);
        settings_box.append (colors_group);

        var settings_dialog = new Adw.AlertDialog (null, null) {
            body_use_markup = true,
            default_response = "save",
            extra_child = settings_box,
        };
        settings_dialog.add_response ("close", _("_Cancel"));

        settings_dialog.add_response ("reset", _("_Reset to Default"));
        settings_dialog.set_response_appearance ("reset", Adw.ResponseAppearance.DESTRUCTIVE);

        settings_dialog.add_response ("save", _("_Save"));
        settings_dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

        settings_dialog.present (this);

        settings_dialog.response.connect ((response_id) => {
            switch (response_id) {
                case "save":
                    string new_server = server_entry.text;
                    string new_color_light = color_light_button.get_rgba ().to_string ();
                    string new_color_dark = color_dark_button.get_rgba ().to_string ();

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

                    if (
                        new_color_light != current_color_light ||
                        new_color_dark != current_color_dark
                    ) {
                        App.settings.set (
                            "headerbar-colors", "(ss)", new_color_light, new_color_dark
                        );
                        update_headerbar_colors (new_color_light, new_color_dark);
                    }
                    break;

                case "reset":
                    App.settings.reset ("headerbar-colors");
                    App.settings.reset ("server");

                    string color_light, color_dark;
                    App.settings.get ("headerbar-colors", "(ss)", out color_light, out color_dark);
                    update_headerbar_colors (color_light, color_dark);

                    log_out ();
                    break;

                case "close":
                default:
                    break;
            }
        });
    }

    private void on_log_out_activate () {
        string server = App.settings.get_string ("server");

        var log_out_dialog = new Adw.AlertDialog (
            _("Log out of Home Assistant?"),
            _("You will need to re-enter your username and password for <b>%s</b> to log back in.").printf (server)
        ) {
            body_use_markup = true,
            default_response = "log_out"
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
