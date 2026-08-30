import Toybox.Graphics;
import Toybox.Lang;

//! The place each board sits in. None of it is interactive and none of it
//! moves: it is drawn from fixed tables in design space so the cost is a
//! couple of dozen fills a frame, and it stays dark enough that the AMOLED
//! panel is still mostly switched off.
//!
//! The trails matter more than the decoration. They run from the yard to each
//! node and on to the machine, so the paths the crew walks are readable as
//! paths even when nobody is standing on them.
module Scenery {

    // One palette per area: forest, quarry, mine, flax field.
    const GROUND = [0x07150A, 0x14140F, 0x120C0C, 0x161206];
    const GROUND_EDGE = [0x102A14, 0x24241C, 0x1E1414, 0x2A240C];
    const TRAIL = [0x241C14, 0x2A2A24, 0x241A16, 0x2C2412];
    const DETAIL = [0x15401F, 0x33383C, 0x3A2A24, 0x4A4418];
    const HORIZON_ART = [0x0E3A1C, 0x2A3038, 0x241C28, 0x3C3A14];

    //! What stands along the top of the glass: 0 a treeline, 1 a ridge.
    const HORIZON_STYLE = [0, 1, 1, 0];

    //! Where the ground starts, in design space.
    const HORIZON = 196;

    //! Treeline: [x, baseY, halfWidth, height].
    const TREELINE = [
        [86, 96, 16, 34], [120, 88, 13, 28], [150, 94, 15, 32],
        [262, 94, 15, 32], [292, 86, 13, 30], [326, 98, 17, 34],
        [58, 132, 14, 28], [356, 134, 14, 28]
    ];

    //! Ridge: the same slots, but drawn as leaning crags.
    const RIDGE = [
        [82, 100, 22, 40], [126, 92, 18, 32], [156, 98, 16, 26],
        [258, 98, 16, 26], [288, 90, 18, 34], [330, 102, 22, 42],
        [56, 136, 16, 24], [358, 138, 16, 24]
    ];

    //! Scatter on the ground: [x, y].
    const SCATTER = [
        [70, 232], [98, 300], [150, 250], [176, 306], [236, 246],
        [268, 302], [318, 236], [344, 292], [206, 288], [128, 214],
        [300, 210], [378, 250], [40, 264]
    ];

    //! Boulders and stumps, a size apiece: [x, y, radius].
    const LUMPS = [
        [64, 208, 7], [352, 210, 6], [170, 336, 5], [246, 334, 5], [206, 258, 4]
    ];

    //! Draw everything behind the game objects.
    function draw(dc as Dc, area as Area, dim as Boolean) as Void {
        var id = area.id;
        drawGround(dc, id, dim);
        drawHorizon(dc, id, dim);
        if (!dim) {
            drawTrails(dc, area);
            drawScatter(dc, id);
        }
    }

    //! The clearing floor, drawn as the top of a very large circle. A plain
    //! band would put a ruled horizontal line across a round screen; a circle
    //! this big reads as ground curving away, and costs one fill either way.
    const GROUND_BULGE = 700;

    function drawGround(dc as Dc, id as Number, dim as Boolean) as Void {
        var r = Layout.s(GROUND_BULGE);
        var cy = Layout.s(HORIZON) + r;
        dc.setColor(pick(GROUND_EDGE, id, dim), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(Layout.cx, cy, r);
        dc.setColor(pick(GROUND, id, dim), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(Layout.cx, cy + Layout.s(4), r);
    }

    //! A treeline or a ridge behind the board, depending on the area.
    function drawHorizon(dc as Dc, id as Number, dim as Boolean) as Void {
        var style = (HORIZON_STYLE as Array<Number>)[id];
        var table = (style == 0 ? TREELINE : RIDGE) as Array<Array<Number> >;
        dc.setColor(pick(HORIZON_ART, id, dim), Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < table.size(); i += 1) {
            var t = table[i];
            var x = Layout.s(t[0]);
            var y = Layout.s(t[1]);
            var half = Layout.s(t[2]);
            var tall = Layout.s(t[3]);
            if (style == 0) {
                dc.fillPolygon([
                    [x, y - tall] as [Numeric, Numeric],
                    [x - half, y] as [Numeric, Numeric],
                    [x + half, y] as [Numeric, Numeric]
                ] as Array<[Numeric, Numeric]>);
            } else {
                // A crag: an off-centre peak with a broken shoulder, so the
                // ridge does not read as a row of identical triangles.
                dc.fillPolygon([
                    [x - half / 3, y - tall] as [Numeric, Numeric],
                    [x + half, y] as [Numeric, Numeric],
                    [x - half, y] as [Numeric, Numeric],
                    [x - half / 2, y - tall / 2] as [Numeric, Numeric]
                ] as Array<[Numeric, Numeric]>);
            }
        }
    }

    //! Worn paths from the yard out to every node, and on to the machine.
    function drawTrails(dc as Dc, area as Area) as Void {
        dc.setColor((TRAIL as Array<Number>)[area.id], Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(Layout.s(7));
        var sx = Layout.s(area.storageX.toNumber());
        var sy = Layout.s(area.storageY.toNumber());
        for (var i = 0; i < area.nodes.size(); i += 1) {
            var node = area.nodes[i];
            dc.drawLine(sx, sy, Layout.s(node.x.toNumber()), Layout.s(node.y.toNumber()));
        }
        dc.drawLine(sx, sy, Layout.s(area.machineX.toNumber()),
            Layout.s(area.machineY.toNumber()));
        dc.setPenWidth(1);
    }

    //! Lumps on the ground, then a scatter of tufts or grit over them.
    function drawScatter(dc as Dc, id as Number) as Void {
        var lumps = LUMPS as Array<Array<Number> >;
        dc.setColor(pick(GROUND_EDGE, id, false), Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < lumps.size(); i += 1) {
            var lump = lumps[i];
            dc.fillCircle(Layout.s(lump[0]), Layout.s(lump[1]), Layout.s(lump[2]));
        }

        var scatter = SCATTER as Array<Array<Number> >;
        dc.setColor((DETAIL as Array<Number>)[id], Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(Layout.s(2));
        for (var i = 0; i < scatter.size(); i += 1) {
            var spot = scatter[i];
            var x = Layout.s(spot[0]);
            var y = Layout.s(spot[1]);
            var h = Layout.s(6);
            dc.drawLine(x, y, x, y - h);
            dc.drawLine(x, y, x - Layout.s(4), y - h);
            dc.drawLine(x, y, x + Layout.s(4), y - h);
        }
        dc.setPenWidth(1);
    }

    //! A locked area is shown, not hidden - seeing the place is what makes
    //! the price a goal - but it is drawn almost black so the unlock card in
    //! front of it stays the only thing worth reading.
    function pick(table as Array<Number>, id as Number, dim as Boolean) as Number {
        var color = table[id];
        if (!dim) {
            return color;
        }
        var r = ((color >> 16) & 0xFF) / 3;
        var g = ((color >> 8) & 0xFF) / 3;
        var b = (color & 0xFF) / 3;
        return (r << 16) | (g << 8) | b;
    }
}
