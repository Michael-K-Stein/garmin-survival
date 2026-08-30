import Toybox.Graphics;
import Toybox.Lang;

//! Colours and the handful of shared drawing primitives. The palette is dark
//! on purpose: the Venu 2 is AMOLED, so black pixels cost no battery.
module Theme {

    const BG = 0x000000;
    const PANEL = 0x101810;
    const PANEL_HI = 0x1C2A1C;
    const CASH = 0x2ED573;
    const CASH_DIM = 0x1B7A42;
    const TEXT = 0xFFFFFF;
    const TEXT_DIM = 0x90A090;
    const WOOD = 0xC08040;
    const LEAF = 0x2E9B4B;
    const LEAF_DIM = 0x1A5C2C;
    const PLAYER = 0x4FC3E8;
    const WORKER = 0xFFC61E;
    const MILL = 0xE07A3A;
    const STORAGE = 0x8C6A4A;
    const BAD = 0xE04030;

    //! One colour per area for its harvest sites and its machine, so a glance
    //! at the board says which of the four you are standing in.
    const NODE_MAIN = [0x2E9B4B, 0x9AA3AA, 0xE0A020, 0xC2CC66];
    const NODE_DIM = [0x1A5C2C, 0x5A6169, 0x6E5A2A, 0x6E7434];
    const MACHINE_COLOR = [0xE07A3A, 0x7FA8C9, 0xD4452A, 0xB06AC9];

    const GAP = 3;

    function nodeMain(area as Number) as Number {
        return (NODE_MAIN as Array<Number>)[area];
    }

    function nodeDim(area as Number) as Number {
        return (NODE_DIM as Array<Number>)[area];
    }

    function machineColor(area as Number) as Number {
        return (MACHINE_COLOR as Array<Number>)[area];
    }

    //! Filled panel with a lighter edge, the basic surface of every screen.
    function panel(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                   radius as Number, fill as Number, edge as Number or Null) as Void {
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, radius);
        if (edge != null) {
            dc.setColor(edge, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawRoundedRectangle(x, y, w, h, radius);
            dc.setPenWidth(1);
        }
    }

    //! A pill-shaped button; hit testing lives with the view that placed it.
    function button(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                    label as String, fill as Number, textColor as Number) as Void {
        dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, h / 2);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w / 2, y + h / 2, Graphics.FONT_TINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Horizontal fill bar, progress 0..1.
    function bar(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                 progress as Float, fill as Number, back as Number) as Void {
        dc.setColor(back, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, h / 2);
        var p = progress;
        if (p < 0.0) {
            p = 0.0;
        }
        if (p > 1.0) {
            p = 1.0;
        }
        var filled = (w * p).toNumber();
        if (filled > 0) {
            dc.setColor(fill, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, y, filled, h, h / 2);
        }
    }

    //! Progress ring from 12 o'clock, sweeping clockwise.
    function ring(dc as Dc, x as Number, y as Number, radius as Number,
                  width as Number, progress as Float, color as Number) as Void {
        dc.setPenWidth(width);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (progress >= 0.999) {
            dc.drawCircle(x, y, radius);
        } else if (progress > 0.01) {
            var end = 90.0 - 360.0 * progress;
            while (end < 0.0) {
                end += 360.0;
            }
            dc.drawArc(x, y, radius, Graphics.ARC_CLOCKWISE, 90, end.toNumber());
        }
        dc.setPenWidth(1);
    }

    //! Large money figure centred at (x, y): the digits in a numeric face,
    //! with the dollar sign and any magnitude suffix beside them in a text
    //! font, all three sharing a baseline.
    //!
    //! They are drawn separately because Garmin's FONT_NUMBER_* faces carry
    //! digits only - a '$' or a 'K' drawn in one comes out as an empty box.
    function bigCash(dc as Dc, x as Number, y as Number, value as Double,
                     color as Number, numberFont as FontType) as Void {
        var p = Fmt.parts(value);
        var sideFont = Graphics.FONT_SMALL;
        var drop = baseline(dc, numberFont) - baseline(dc, sideFont);

        var digits = p[0];
        var suffix = p[1];
        var digitsW = dc.getTextWidthInPixels(digits, numberFont);
        var signW = dc.getTextWidthInPixels("$", sideFont);
        var suffixW = suffix.equals("") ? 0 : dc.getTextWidthInPixels(suffix, sideFont);

        var total = signW + GAP + digitsW;
        if (suffixW > 0) {
            total += GAP + suffixW;
        }
        var left = x - total / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, y + drop, sideFont, "$", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(left + signW + GAP, y, numberFont, digits, Graphics.TEXT_JUSTIFY_LEFT);
        if (suffixW > 0) {
            dc.drawText(left + signW + GAP + digitsW + GAP, y + drop, sideFont, suffix,
                Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    //! Pixels from the top of a font's line box to its baseline.
    function baseline(dc as Dc, font as FontType) as Number {
        if (Graphics has :getFontAscent) {
            return Graphics.getFontAscent(font);
        }
        return dc.getFontHeight(font);
    }
}
