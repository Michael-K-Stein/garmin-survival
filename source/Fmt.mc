import Toybox.Lang;

//! Presentation helpers. Everything is squeezed to three significant digits
//! plus a short magnitude suffix, because a 416px round screen has no room
//! for a seven-digit bank balance.
module Fmt {

    const SUFFIX = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx"];

    //! Split a value into digits and magnitude suffix: 1234567 -> ["1.23", "M"].
    //!
    //! The halves stay separate because Garmin's FONT_NUMBER_* faces are
    //! digit-only: a letter drawn in one renders as nothing at all.
    function parts(value as Double) as Array<String> {
        var v = value;
        if (v < 0.0d) {
            v = 0.0d;
        }
        if (v < 1000.0d) {
            return [v.toNumber().toString(), ""] as Array<String>;
        }

        var tier = 0;
        var last = SUFFIX.size() - 1;
        while (v >= 1000.0d && tier < last) {
            v /= 1000.0d;
            tier += 1;
        }

        var text;
        if (v < 10.0d) {
            text = v.format("%.2f");
        } else if (v < 100.0d) {
            text = v.format("%.1f");
        } else {
            text = v.format("%.0f");
        }
        return [text, (SUFFIX as Array<String>)[tier]] as Array<String>;
    }

    //! 1234567 -> "1.23M".
    function big(value as Double) as String {
        var p = parts(value);
        return p[0] + p[1];
    }

    //! Money, with the sign the buttons want: "$1.23M".
    function cash(value as Double) as String {
        return "$" + big(value);
    }

    //! Rates keep a decimal while they are still small, so a one-worker
    //! operation visibly moves.
    function rate(value as Double) as String {
        if (value > 0.0d && value < 100.0d) {
            return value.format("%.1f");
        }
        return big(value);
    }

    //! "3h 12m", "12m 05s", "48s".
    function duration(seconds as Number) as String {
        var s = seconds;
        if (s < 0) {
            s = 0;
        }
        var h = s / 3600;
        var m = (s % 3600) / 60;
        var sec = s % 60;
        if (h > 0) {
            return h.toString() + "h " + m.format("%02d") + "m";
        }
        if (m > 0) {
            return m.toString() + "m " + sec.format("%02d") + "s";
        }
        return sec.toString() + "s";
    }
}
