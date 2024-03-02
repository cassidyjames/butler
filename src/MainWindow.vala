/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2024 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.MainWindow : Adw.ApplicationWindow {
    public Adw.AboutWindow about_window;
    public Adw.Banner demo_banner;
    public Adw.Toast fullscreen_toast;
    public Adw.ToastOverlay toast_overlay;
    public Gtk.Revealer header_revealer;
    public Gtk.Revealer home_revealer;

    private const GLib.ActionEntry[] ACTION_ENTRIES = {
        { "toggle_fullscreen", toggle_fullscreen },
        { "set_server", on_set_server_activate },
        { "log_out", on_log_out_activate },
        { "about", on_about_activate },
    };

    private Butler.WebView web_view;

    public MainWindow (Gtk.Application application) {
        Object (
            application: application,
            height_request: 180,
            resizable: true,
            width_request: 300
        );
        add_action_entries (ACTION_ENTRIES, this);
    }

    construct {
        maximized = App.settings.get_boolean ("window-maximized");
        fullscreened = App.settings.get_boolean ("window-fullscreened");

        about_window = new Adw.AboutWindow.from_appdata (
            "/com/cassidyjames/butler/metainfo.xml", VERSION
        ) {
            transient_for = this,
            hide_on_close = true,
            comments = _("Companion app to access your Home Assistant dashboard"),

            /// The translator credits. Please translate this with your name(s).
            translator_credits = _("translator-credits"),
            artists = {
                "Jakub Steiner https://jimmac.eu/",
                "Tobias Bernard https://tobiasbernard.com/",
            },
        };
        about_window.copyright = "© 2020–%i %s".printf (
            new DateTime.now_local ().get_year (),
            about_window.developer_name
        );
        about_window.add_link (_("About Home Assistant"), "https://www.home-assistant.io/");
        about_window.add_link (_("Home Assistant Privacy Policy"), "https://www.home-assistant.io/privacy/");

        // Set MainWindow properties from the AppData already fetched and parsed
        // by the AboutWindow construction
        icon_name = about_window.application_icon;
        title = about_window.application_name;

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
        app_menu.append (_("Change _Server…"), "win.set_server");
        app_menu.append (_("_About %s").printf (title), "win.about");

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
            action_name = "win.set_server",
            button_label = _("Set _Server…")
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

        toast_overlay = new Adw.ToastOverlay () {
            child = stack
        };

        var grid = new Gtk.Grid () {
            orientation = Gtk.Orientation.VERTICAL
        };
        grid.attach (header_revealer, 0, 0);
        grid.attach (toast_overlay, 0, 1);
        grid.attach (demo_banner, 0, 2);

        set_content (grid);

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

    private void on_set_server_activate () {
        string current_server = App.settings.get_string ("server");
        string default_server = App.settings.get_default_value ("server").get_string ();

        var server_entry = new Gtk.Entry.with_buffer (new Gtk.EntryBuffer ((uint8[]) current_server)) {
            activates_default = true,
            hexpand = true,
            placeholder_text = default_server
        };

        var server_dialog = new Adw.MessageDialog (
            this,
            _("Set Server URL"),
            _("Enter the full URL including any custom port")
        ) {
            body_use_markup = true,
            default_response = "save",
            extra_child = server_entry,
        };
        server_dialog.add_response ("close", _("_Cancel"));

        server_dialog.add_response ("demo", _("_Reset to Demo"));
        server_dialog.set_response_appearance ("demo", Adw.ResponseAppearance.DESTRUCTIVE);

        server_dialog.add_response ("save", _("_Set Server"));
        server_dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);

        server_dialog.present ();

        server_dialog.response.connect ((response_id) => {
            if (response_id == "save") {
                string new_server = server_entry.buffer.text;

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
            } else if (response_id == "demo") {
                App.settings.reset ("server");
                log_out ();
            }
        });
    }

    private void on_log_out_activate () {
        string server = App.settings.get_string ("server");

        var log_out_dialog = new Adw.MessageDialog (
            this,
            _("Log out of Home Assistant?"),
            _("You will need to re-enter your username and password for <b>%s</b> to log back in.").printf (server)
        ) {
            body_use_markup = true,
            default_response = "log_out"
        };
        log_out_dialog.add_response ("close", _("_Stay Logged In"));
        log_out_dialog.add_response ("log_out", _("_Log Out"));
        log_out_dialog.set_response_appearance ("log_out", Adw.ResponseAppearance.DESTRUCTIVE);

        log_out_dialog.present ();

        log_out_dialog.response.connect ((response_id) => {
            if (response_id == "log_out") {
                log_out ();
            }
        });
    }

    private void on_about_activate () {
        about_window.present ();
    }
}

