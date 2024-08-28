/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2020–2024 Cassidy James Blaede <c@ssidyjam.es>
 */

namespace Butler {

    private static double contrast_ratio (Gdk.RGBA bg_color, Gdk.RGBA fg_color) {
        // From WCAG 2.0 https://www.w3.org/TR/WCAG20/#contrast-ratiodef
        var bg_luminance = get_luminance (bg_color);
        var fg_luminance = get_luminance (fg_color);

        if (bg_luminance > fg_luminance) {
            return (bg_luminance + 0.05) / (fg_luminance + 0.05);
        }

        return (fg_luminance + 0.05) / (bg_luminance + 0.05);
    }

    private static double get_luminance (Gdk.RGBA color) {
        // Values from WCAG 2.0 https://www.w3.org/TR/WCAG20/#relativeluminancedef
        var red = sanitize_color (color.red) * 0.2126;
        var green = sanitize_color (color.green) * 0.7152;
        var blue = sanitize_color (color.blue) * 0.0722;

        return red + green + blue;
    }

    private static double sanitize_color (double color) {
        // From WCAG 2.0 https://www.w3.org/TR/WCAG20/#relativeluminancedef
        if (color <= 0.03928) {
            return color / 12.92;
        }

        return Math.pow ((color + 0.055) / 1.055, 2.4);
    }

    /**
     * Takes a {@link Gdk.RGBA} background color and returns a suitably-contrasting foreground color, i.e. for determining text color on a colored background. There is a slight bias toward returning white, as white generally looks better on a wider range of colored backgrounds than black.
     *
     * Copied from my implementation in Granite https://github.com/elementary/granite/commit/74b7e4318dc7721a6c09dd6bf67713299d7be8eb
     *
     * @param bg_color any {@link Gdk.RGBA} background color
     *
     * @return a contrasting {@link Gdk.RGBA} foreground color, i.e. white ({ 1.0, 1.0, 1.0, 1.0}) or black ({ 0.0, 0.0, 0.0, 1.0}).
     */
    public static Gdk.RGBA contrasting_foreground_color (Gdk.RGBA bg_color) {
        Gdk.RGBA gdk_white = { 1.0f, 1.0f, 1.0f, 1.0f };
        Gdk.RGBA gdk_black = { 0.0f, 0.0f, 0.0f, 1.0f };

        var contrast_with_white = contrast_ratio (
            bg_color,
            gdk_white
        );
        var contrast_with_black = contrast_ratio (
            bg_color,
            gdk_black
        );

        // Default to white
        var fg_color = gdk_white;

        // NOTE: We cheat and add 6 to contrast when checking against black,
        // because white generally looks better on a colored background
        if ( contrast_with_black > (contrast_with_white + 6) ) {
            fg_color = gdk_black;
        }

        return fg_color;
    }
}
