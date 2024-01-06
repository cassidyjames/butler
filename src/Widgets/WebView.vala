/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2024 Cassidy James Blaede <c@ssidyjam.es>
 */

public class Butler.WebView : WebKit.WebView {
    private bool is_terminal = false;

    public WebView () {
        Object (
            hexpand: true,
            vexpand: true
        );
    }

    construct {
        is_terminal = Posix.isatty (Posix.STDIN_FILENO);

        var webkit_settings = new WebKit.Settings () {
            default_font_family = Gtk.Settings.get_default ().gtk_font_name,
            enable_back_forward_navigation_gestures = true,
            enable_developer_extras = is_terminal,
            enable_dns_prefetching = true,
            enable_html5_database = true,
            enable_html5_local_storage = true,
            enable_smooth_scrolling = true,
            enable_webgl = true,
            enable_webrtc = true,
            hardware_acceleration_policy = WebKit.HardwareAccelerationPolicy.ALWAYS
        };

        settings = webkit_settings;

        context_menu.connect (() => {
            return !is_terminal;
        });

        decide_policy.connect ((decision, type) => {
            if (type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
                try {
                    new Gtk.UriLauncher (
                        ((WebKit.NavigationPolicyDecision)decision).
                        navigation_action.get_request ().get_uri ()
                    ).launch.begin (null, null);
                } catch (Error e) {
                    critical ("Unable to open externally");
                }
            }
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

