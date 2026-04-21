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
        { "open_file", on_open_file_activate, "s" },
        { "zoom-out", zoom_out },
        { "zoom-default", zoom_default },
        { "zoom-in", zoom_in },
        { "reload", on_reload_activate },
        { "settings", on_settings_activate },
        { "log_out", on_log_out_activate },
        { "about", on_about_activate },
    };

    [GtkChild] private unowned Gtk.Revealer header_revealer;
    [GtkChild] private unowned Gtk.Revealer home_revealer;
    [GtkChild] private unowned Gtk.Button home_button;
    [GtkChild] private unowned Adw.Toast fullscreen_toast;
    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Gtk.Button open_button;
    [GtkChild] private unowned Adw.Banner demo_banner;
    [GtkChild] private unowned Gtk.Stack stack;
    [GtkChild] private unowned Adw.StatusPage loading_page;
    [GtkChild] private unowned Adw.StatusPage error_page;
    [GtkChild] private unowned Gtk.Button error_retry_button;

    [GtkChild] private unowned Gtk.Label zoom_label;
    [GtkChild] private unowned Gtk.MenuButton download_button;

    private Adw.AboutDialog about_dialog;
    private Butler.WebView web_view;
    private Gtk.Box downloads_box;
    private string? last_failed_uri = null;
    private int active_downloads = 0;
    private bool mouse_at_top = false;
    private uint hide_timeout_id = 0;

    private const string CSS = """
        :root {
          --headerbar-bg-light: %s;
          --headerbar-fg-light: %s;

          --headerbar-bg-dark: %s;
          --headerbar-fg-dark: %s;
        }
    """;
    private Gtk.CssProvider css_provider = new Gtk.CssProvider ();

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

        var motion = new Gtk.EventControllerMotion ();
        motion.motion.connect ((x, y) => {
            bool in_header_zone = y <= 8 ||
                (header_revealer.child_revealed && y <= header_revealer.get_height ());
            if (in_header_zone) {
                if (hide_timeout_id != 0) {
                    Source.remove (hide_timeout_id);
                    hide_timeout_id = 0;
                }
                if (!mouse_at_top) {
                    mouse_at_top = true;
                    update_header_visibility ();
                }
            } else if (mouse_at_top && hide_timeout_id == 0) {
                hide_timeout_id = Timeout.add (500, () => {
                    hide_timeout_id = 0;
                    mouse_at_top = false;
                    update_header_visibility ();
                    return Source.REMOVE;
                });
            }
        });
        // NOTE: cast to avoid trying to convert to Gtk.ShortcutController
        ((Gtk.Widget) this).add_controller (motion);

        update_header_visibility ();

        loading_page.title = APP_NAME;
        loading_page.description = _("Loading the dashboard…");
        loading_page.icon_name = APP_ID;

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
        about_dialog.copyright = "© 2020–2026 %s".printf (
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

        web_view.notify["zoom-level"].connect (() => {
            zoom_label.label = zoom_label_text ();
        });

        downloads_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12) {
            margin_top = 6,
            margin_bottom = 6,
            margin_start = 6,
            width_request = 250,
        };
        (download_button.popover).child = downloads_box;

        web_view.download_started.connect ((download, filename) => {
            active_downloads++;
            download_button.visible = true;

            var name_label = new Gtk.Label (filename) {
                halign = Gtk.Align.START,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 30,
            };

            var progress_bar = new Gtk.ProgressBar ();

            var size_label = new Gtk.Label ("") {
                halign = Gtk.Align.START,
            };
            size_label.add_css_class ("dimmed");
            size_label.add_css_class ("numeric");

            var download_info = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            download_info.append (name_label);
            download_info.append (progress_bar);
            download_info.append (size_label);

            var cancel_button = new Gtk.Button.from_icon_name ("process-stop-symbolic") {
                tooltip_text = _("Cancel"),
                valign = Gtk.Align.CENTER,
            };
            cancel_button.add_css_class ("flat");
            cancel_button.add_css_class ("circular");
            cancel_button.clicked.connect (download.cancel);

            var download_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            download_row.append (download_info);
            download_row.append (cancel_button);

            downloads_box.append (download_row);

            uint64 bytes_received = 0;
            var failed = false;

            uint pulse_timer_id = Timeout.add (100, () => {
                progress_bar.pulse ();
                return Source.CONTINUE;
            });

            download.received_data.connect ((chunk_length) => {
                bytes_received += chunk_length;
                uint64 total = download.response.content_length;
                if (total > 0) {
                    if (pulse_timer_id > 0) {
                        Source.remove (pulse_timer_id);
                        pulse_timer_id = 0;
                    }
                    progress_bar.fraction = (double) bytes_received / (double) total;
                    size_label.label = "%s / %s".printf (
                        GLib.format_size (bytes_received),
                        GLib.format_size (total)
                    );
                } else {
                    size_label.label = GLib.format_size (bytes_received);
                }
            });

            download.failed.connect ((error) => {
                failed = true;
                if (pulse_timer_id > 0) {
                    Source.remove (pulse_timer_id);
                    pulse_timer_id = 0;
                }

                active_downloads--;
                downloads_box.remove (download_row);

                if (active_downloads == 0) {
                    download_button.visible = false;
                }
            });

            download.finished.connect (() => {
                if (failed) {
                    return;
                }

                if (pulse_timer_id > 0) {
                    Source.remove (pulse_timer_id);
                    pulse_timer_id = 0;
                }

                active_downloads--;
                downloads_box.remove (download_row);

                if (active_downloads == 0) {
                    download_button.visible = false;
                }

                if (!failed) {
                    var file = File.new_for_path (download.get_destination ());
                    var complete_toast = new Adw.Toast (
                        _("Downloaded “%s”").printf (file.get_basename ())
                    ) {
                        button_label = _("Open"),
                        action_name = "win.open_file",
                        timeout = 0
                    };
                    complete_toast.set_action_target ("s", file.get_uri ());
                    toast_overlay.add_toast (complete_toast);
                }
            });
        });

        string headerbar_color_light, headerbar_color_dark;
        App.settings.get (
            "headerbar-colors",
            "(ss)",
            out headerbar_color_light,
            out headerbar_color_dark
        );
        update_headerbar_colors (headerbar_color_light, headerbar_color_dark);
        add_css_provider_for_display (
            Gdk.Display.get_default (),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
        );

        int window_width, window_height;
        App.settings.get (
            "window-size",
            "(ii)",
            out window_width,
            out window_height
        );

        set_default_size (window_width, window_height);

        home_button.clicked.connect (() => {
            web_view.load_uri (App.settings.get_string ("server"));
        });

        var fullscreen_action = new GLib.SimpleAction.stateful (
            "toggle_fullscreen", null, new GLib.Variant.boolean (fullscreened)
        );
        fullscreen_action.activate.connect (toggle_fullscreen);
        add_action (fullscreen_action);

        App.settings.changed["autohide-titlebar"].connect (update_header_visibility);
        notify["fullscreened"].connect (() => {
            fullscreen_action.set_state (new GLib.Variant.boolean (fullscreened));
            update_header_visibility ();
        });

        close_request.connect (() => {
            if (web_view.uri != null) {
                App.settings.set_string ("current-url", web_view.uri);
            }
            save_window_state ();
            return Gdk.EVENT_PROPAGATE;
        });
        notify["fullscreened"].connect (save_window_state);
        notify["maximized"].connect (save_window_state);

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

        open_button.clicked.connect (() => {
            new Gtk.UriLauncher (web_view.uri).launch.begin (this, null);
        });

        web_view.load_changed.connect (on_loading);

        App.settings.bind ("zoom", web_view, "zoom-level", SettingsBindFlags.DEFAULT);
    }

    private string zoom_label_text () {
        return "%d%%".printf ((int) GLib.Math.round (web_view.zoom_level * 100));
    }

    private void update_headerbar_colors (string light, string dark) {
        var light_rgba = Gdk.RGBA ();
        light_rgba.parse (light);

        var dark_rgba = Gdk.RGBA ();
        dark_rgba.parse (dark);

        var css = CSS.printf (
            light_rgba.to_string (),
            contrasting_foreground_color (light_rgba).to_string (),
            dark_rgba.to_string (),
            contrasting_foreground_color (dark_rgba).to_string ()
        );

        css_provider.load_from_string (css);
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

    private void on_loading (WebKit.LoadEvent load_event) {
        if (load_event == WebKit.LoadEvent.STARTED) {
            last_failed_uri = null;
            if (stack.visible_child_name == "error" || stack.visible_child_name == "not-ha") {
                stack.visible_child_name = "loading";
            }
            return;
        }

        if (load_event != WebKit.LoadEvent.FINISHED) {
            return;
        }

        if (last_failed_uri != null) {
            demo_banner.revealed = false;
            return;
        }

        stack.visible_child_name = "web";
        home_revealer.reveal_child = false;

        string default_server = App.settings.get_default_value ("server").get_string ();
        string server = App.settings.get_string ("server");
        string current_url = web_view.uri;

        if (current_url.has_prefix (default_server)) {
            demo_banner.revealed = true;
        } else if (current_url.has_prefix (server)) {
            demo_banner.revealed = false;
        } else {
            // Somehow you got away from the server without opening a link in
            // the browser…
            demo_banner.revealed = false;
            home_revealer.reveal_child = true;
        }

        if (current_url.has_prefix (default_server)) {
            return;
        }

        web_view.evaluate_javascript.begin (
            "document.querySelector('home-assistant, ha-authorize') !== null",
            -1, null, null, null,
            (obj, res) => {
                try {
                    var js_result = web_view.evaluate_javascript.end (res);
                    if (!js_result.to_boolean ()) {
                        stack.visible_child_name = "not-ha";
                    }
                } catch (Error e) {
                    // Ignore JS errors; leave page visible
                }
            }
        );
    }

    private void zoom_in () {
        if (web_view.zoom_level < 4.9) {
            web_view.zoom_level = web_view.zoom_level + 0.1;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already max");
        }
    }

    private void zoom_out () {
        if (web_view.zoom_level > 0.3) {
            web_view.zoom_level = web_view.zoom_level - 0.1;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already min");
        }
    }

    private void zoom_default () {
        if (web_view.zoom_level != 1.0) {
            web_view.zoom_level = 1.0;
        } else {
            Gdk.Display.get_default ().beep ();
            warning ("Zoom already default");
        }
    }

    private void log_out () {
        web_view.network_session.get_website_data_manager ().clear.begin (
            WebKit.WebsiteDataTypes.ALL, 0, null, () => {
                debug ("Cleared data; going home.");
                web_view.load_uri (App.settings.get_string ("server"));
            }
        );
    }

    private void toggle_fullscreen () {
        if (fullscreened) {
            unfullscreen ();
            fullscreen_toast.dismiss ();
        } else {
            fullscreen ();
            toast_overlay.add_toast (fullscreen_toast);
        }
    }

    private void update_header_visibility () {
        bool autohide = App.settings.get_boolean ("autohide-titlebar");
        header_revealer.reveal_child = (!autohide && !fullscreened) || mouse_at_top;
    }

    private void on_reload_activate () {
        web_view.reload ();
    }

    private void on_open_file_activate (SimpleAction action, Variant? parameter) {
        if (parameter != null) {
            new Gtk.FileLauncher (File.new_for_uri (parameter.get_string ())).launch.begin (this, null);
        }
    }

    private void on_settings_activate () {
        var settings_dialog = new Butler.SettingsDialog ();
        settings_dialog.server_changed.connect (() => {
            web_view.load_uri (App.settings.get_string ("server"));
        });
        settings_dialog.colors_changed.connect (update_headerbar_colors);
        settings_dialog.present (this);
    }

    private void on_log_out_activate () {
        string server = App.settings.get_string ("server");

        var log_out_dialog = new Adw.AlertDialog (
            _("Log out of Home Assistant?"),
            _("You will need to log back in to <b>%s</b> or any previously-used servers.").printf (server)
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
