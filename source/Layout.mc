import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! The board is authored against a 416x416 round face and scaled to whatever
//! the device actually has, so the Venu 2S (360x360) gets the same layout
//! rather than a cropped one.
module Layout {

    const DESIGN = 416.0;

    var scale as Float = 1.0;
    var width as Number = 416;
    var height as Number = 416;
    var cx as Number = 208;
    var cy as Number = 208;
    var radius as Number = 208;

    //! Called once per draw, before anything is positioned.
    function measure(dc as Dc) as Void {
        width = dc.getWidth();
        height = dc.getHeight();
        cx = width / 2;
        cy = height / 2;
        radius = (width < height) ? width / 2 : height / 2;
        scale = width / DESIGN;
    }

    //! Design-space length to device pixels.
    function s(value as Number or Float) as Number {
        return (value * scale + 0.5).toNumber();
    }

    //! Half-width of the round glass at a given vertical offset from the
    //! centre. Used to keep panels and text off the bezel.
    function chordHalfWidth(dy as Number) as Number {
        var d = dy.abs();
        if (d >= radius) {
            return 0;
        }
        return Math.sqrt((radius * radius - d * d).toFloat()).toNumber();
    }

    //! The widest rectangle of height `h` that fits inside the glass with its
    //! top at `y`, inset from the bezel. Returns [x, w].
    function fitRow(y as Number, h as Number, inset as Number) as Array<Number> {
        var top = chordHalfWidth(y - cy);
        var bottom = chordHalfWidth(y + h - cy);
        var half = (top < bottom) ? top : bottom;
        var w = 2 * half - 2 * inset;
        if (w < 0) {
            w = 0;
        }
        return [cx - w / 2, w] as Array<Number>;
    }
}
