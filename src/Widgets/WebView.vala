/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2026 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.WebView : WebKit.WebView {
    private bool is_terminal = false;

    public signal void download_started (WebKit.Download download, string filename);

    public WebView () {
        Object (
            hexpand: true,
            vexpand: true,
            network_session: new WebKit.NetworkSession (null, null)
        );
    }

    construct {
        is_terminal = Posix.isatty (Posix.STDIN_FILENO);

        var webkit_settings = new WebKit.Settings () {
            default_font_family = Gtk.Settings.get_default ().gtk_font_name,
            enable_back_forward_navigation_gestures = true,
            enable_developer_extras = is_terminal,
            enable_html5_database = true,
            enable_html5_local_storage = true,
            enable_smooth_scrolling = true,
            enable_webgl = true,
            enable_webrtc = true
        };

        settings = webkit_settings;

        var cookie_manager = network_session.get_cookie_manager ();
        cookie_manager.set_accept_policy (WebKit.CookieAcceptPolicy.ALWAYS);

        string config_dir = Path.build_path (
            Path.DIR_SEPARATOR_S,
            Environment.get_user_config_dir (),
            Environment.get_prgname ()
        );

        DirUtils.create_with_parents (config_dir, 0700);

        string cookies = Path.build_filename (config_dir, "cookies");
        cookie_manager.set_persistent_storage (
            cookies,
            WebKit.CookiePersistentStorage.SQLITE
        );

        context_menu.connect (() => {
            return !is_terminal;
        });

        decide_policy.connect ((decision, type) => {
            if (type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
                new Gtk.UriLauncher (
                    ((WebKit.NavigationPolicyDecision)decision).
                    navigation_action.get_request ().get_uri ()
                ).launch.begin (null, null);
            } else if (type == WebKit.PolicyDecisionType.RESPONSE) {
                var response_decision = (WebKit.ResponsePolicyDecision) decision;
                if (!response_decision.is_mime_type_supported ()) {
                    response_decision.download ();
                    return true;
                }
            }
            return false;
        });

        network_session.download_started.connect ((dl) => {
            dl.decide_destination.connect ((suggested_filename) => {
                var downloads_dir = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
                DirUtils.create_with_parents (downloads_dir, 0755);

                var path = Path.build_filename (downloads_dir, suggested_filename);
                var file = File.new_for_path (path);
                var i = 1;
                while (file.query_exists ()) {
                    var dot = suggested_filename.last_index_of (".");
                    string new_name;
                    if (dot > 0) {
                        new_name = suggested_filename[0:dot] + " (%d)".printf (i) + suggested_filename[dot:];
                    } else {
                        new_name = suggested_filename + " (%d)".printf (i);
                    }
                    path = Path.build_filename (downloads_dir, new_name);
                    file = File.new_for_path (path);
                    i++;
                }

                dl.set_destination (file.get_path ());
                this.download_started (dl, file.get_basename ());
                return true;
            });
        });

        var back_click_gesture = new Gtk.GestureClick () {
            button = 8
        };
        back_click_gesture.pressed.connect (go_back);
        add_controller (back_click_gesture);

        var forward_click_gesture = new Gtk.GestureClick () {
            button = 9
        };
        forward_click_gesture.pressed.connect (go_forward);
        add_controller (forward_click_gesture);
    }
}
