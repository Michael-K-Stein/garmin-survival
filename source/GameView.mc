import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! The board. One compact area that fits the glass with no camera and no
//! scrolling: three harvest sites, the yard, the machine, whoever is working,
//! and one contextual button along the bottom. Swiping sideways changes which
//! of the four areas is on screen.
class GameView extends WatchUi.View {

    private var mGame as GameState or Null = null;
    private var mTimer as Timer.Timer or Null = null;

    // Bottom button, in device pixels, filled in by onLayout().
    private var mBtnX as Number = 0;
    private var mBtnY as Number = 0;
    private var mBtnW as Number = 0;
    private var mBtnH as Number = 0;

    // A short-lived "+$120" over the yard, driven by Events.
    private var mToast as String = "";
    private var mToastLeft as Float = 0.0;
    //! How long the current toast was given, so it can rise at the same pace
    //! whether it is a sale or a contract.
    private var mToastFor as Float = 1.4;
    // The area name, shown for a moment after a swipe.
    private var mLabelLeft as Float = 0.0;

    // The action the button is currently offering.
    const ACT_COLLECT = 0;
    const ACT_STORE = 1;
    const ACT_SELL = 2;
    const ACT_UNLOCK = 3;
    const ACT_RICH = 4;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        Layout.measure(dc);
        mBtnH = Layout.s(56);
        mBtnY = Layout.s(322);
        var row = Layout.fitRow(mBtnY, mBtnH, Layout.s(8));
        mBtnX = row[0];
        mBtnW = row[1];
    }

    function onShow() as Void {
        mGame = TimberlineApp.game();
        Events.subscribe(method(:onGameEvent));
        if (mTimer == null) {
            mTimer = new Timer.Timer();
            (mTimer as Timer.Timer).start(method(:onTick), Balance.TICK_MS, true);
        }
    }

    function onHide() as Void {
        Events.unsubscribe();
        if (mTimer != null) {
            (mTimer as Timer.Timer).stop();
            mTimer = null;
        }
        var game = mGame;
        if (game != null) {
            game.save();
        }
    }

    function onTick() as Void {
        var game = mGame;
        if (game == null) {
            return;
        }
        game.tick();
        var dt = Balance.TICK_MS / 1000.0;
        if (mToastLeft > 0.0) {
            mToastLeft -= dt;
        }
        if (mLabelLeft > 0.0) {
            mLabelLeft -= dt;
        }
        WatchUi.requestUpdate();
    }

    //! Anything the player would otherwise have to go and look for gets a
    //! moment on the board: money changing hands, a contract signed off, a
    //! mastery level, a vein coming in rich.
    function onGameEvent(name as Number, value as Double) as Void {
        if (name == Events.ITEM_SOLD) {
            toast("+" + Fmt.cash(value), 1.4);
        } else if (name == Events.CONTRACT_DONE) {
            toast("CONTRACT +" + Fmt.cash(value), 2.4);
            Haptics.confirm();
        } else if (name == Events.MASTERY_GAINED) {
            toast("MASTERY " + value.toNumber().toString(), 2.0);
        } else if (name == Events.RICH_VEIN) {
            toast("RICH VEIN", 1.8);
            Haptics.tap();
        }
    }

    private function toast(text as String, secs as Float) as Void {
        mToast = text;
        mToastLeft = secs;
        mToastFor = secs;
    }

    // ------------------------------------------------------------------ input

    //! Move to the next or previous board.
    function changeArea(delta as Number) as Void {
        var game = mGame;
        if (game == null) {
            return;
        }
        game.switchArea(delta);
        mLabelLeft = Balance.AREA_LABEL_SECS;
        Haptics.tap();
        WatchUi.requestUpdate();
    }

    //! Handle a tap in device pixels. Returns true if it hit something.
    function onTapAt(px as Number, py as Number) as Boolean {
        var game = mGame;
        if (game == null) {
            return false;
        }

        if (px >= mBtnX && px <= mBtnX + mBtnW && py >= mBtnY && py <= mBtnY + mBtnH) {
            return doAction(action());
        }

        var here = game.area();
        if (!here.unlocked) {
            // A locked board has exactly one thing you can do with it.
            return doAction(ACT_UNLOCK);
        }

        // Everything else is hit-tested in the board's design space.
        var bx = unscale(px);
        var by = unscale(py);

        if (here.machineUnder(bx, by)) {
            var manage = new ManageView(Page.MACHINE);
            WatchUi.pushView(manage, new ManageDelegate(manage), WatchUi.SLIDE_UP);
            return true;
        }
        if (here.storageUnder(bx, by)) {
            if (game.player.carry > 0.0) {
                game.player.goToStorage();
                Haptics.tap();
                return true;
            }
            return doAction(ACT_SELL);
        }
        var node = here.nodeUnder(bx, by);
        if (node >= 0) {
            game.player.goToNode(node);
            Haptics.tap();
            return true;
        }
        return false;
    }

    //! The single action the bottom button is offering right now.
    function action() as Number {
        var game = mGame;
        if (game == null) {
            return ACT_COLLECT;
        }
        if (!game.area().unlocked) {
            return ACT_UNLOCK;
        }
        // A rich vein outranks everything: it is on a clock, and the yard
        // will still be there afterwards.
        if (game.area().richNode >= 0 && !game.player.isFull()) {
            return ACT_RICH;
        }
        if (game.player.carry > 0.0) {
            return ACT_STORE;
        }
        if (game.area().stock > 0.0) {
            return ACT_SELL;
        }
        return ACT_COLLECT;
    }

    function doAction(what as Number) as Boolean {
        var game = mGame;
        if (game == null) {
            return false;
        }
        if (what == ACT_UNLOCK) {
            if (game.unlockArea()) {
                mLabelLeft = Balance.AREA_LABEL_SECS;
                Haptics.confirm();
                game.save();
                return true;
            }
            Haptics.deny();
            return false;
        }
        if (what == ACT_RICH) {
            var vein = game.area().richNode;
            if (vein < 0) {
                return false;
            }
            game.player.goToNode(vein);
            Haptics.tap();
            return true;
        }
        if (what == ACT_STORE) {
            game.player.goToStorage();
            Haptics.tap();
            return true;
        }
        if (what == ACT_SELL) {
            if (game.sellStock() > 0.0d) {
                Haptics.confirm();
                return true;
            }
            return false;
        }
        var pick = game.area().bestNode(game.player.x, game.player.y);
        if (pick < 0) {
            return false;
        }
        game.player.goToNode(pick);
        Haptics.tap();
        return true;
    }

    // ----------------------------------------------------------------- drawing

    function onUpdate(dc as Dc) as Void {
        Layout.measure(dc);
        dc.setColor(Theme.TEXT, Theme.BG);
        dc.clear();

        var game = mGame;
        if (game == null) {
            return;
        }
        var here = game.area();
        var locked = !here.unlocked;

        Scenery.draw(dc, here, locked);

        if (locked) {
            drawLockCard(dc, here);
        } else {
            for (var i = 0; i < here.nodes.size(); i += 1) {
                drawNode(dc, here, i);
            }
            drawStorage(dc, here);
            drawMachine(dc, here);

            for (var i = 0; i < here.crew.size(); i += 1) {
                drawActor(dc, here.crew[i], Layout.s(9), Theme.WORKER);
            }
            drawActor(dc, game.player, Layout.s(13), Theme.PLAYER);
        }

        drawHeader(dc, game, locked);
        drawAreaDots(dc, game);
        drawAreaLabel(dc, here);
        drawToast(dc);
        drawButton(dc, game, here);
    }

    private function drawHeader(dc as Dc, game as GameState, locked as Boolean) as Void {
        Theme.bigCash(dc, Layout.cx, Layout.s(6), game.cash, Theme.CASH,
            Graphics.FONT_NUMBER_MILD);

        // The hands-off rate sits in the gap just above the horizon rather
        // than under the balance: it is the number that says the operation is
        // running itself, and the band between the canopies is the one strip
        // of the board nothing else ever occupies.
        // A locked board is showing its price; nothing else competes for
        // that space.
        // What every camp before this one is still paying, if there was one.
        if (game.legacy > 0) {
            dc.setColor(Theme.WORKER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Layout.cx, Layout.s(58), Graphics.FONT_XTINY,
                "LEGACY x" + Fmt.rate(game.legacyBonus().toDouble()),
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        var perMin = game.incomePerMinute();
        if (perMin > 0.0d && !locked) {
            dc.setColor(Theme.CASH_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Layout.cx, Layout.s(174), Graphics.FONT_XTINY,
                "+" + Fmt.cash(perMin) + "/min", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    //! Every area draws its nodes differently, because "how much is left" has
    //! to be readable at a glance and a tree does not shrink like a boulder.
    private function drawNode(dc as Dc, area as Area, index as Number) as Void {
        var node = area.nodes[index];
        var x = Layout.s(node.x.toNumber());
        var y = Layout.s(node.y.toNumber());

        // A rich vein is drawn as a ring that visibly runs out, because the
        // whole point of it is that you have to get there before it does.
        if (area.isRich(index)) {
            Theme.ring(dc, x, y, Layout.s(30), Layout.s(3), 1.0, Theme.PANEL_HI);
            Theme.ring(dc, x, y, Layout.s(30), Layout.s(3),
                area.richLeftFraction(), Theme.WORKER);
        }

        if (!node.hasStock()) {
            // A spent site: the stump, a full dim ring for the track, and the
            // bright arc filling it as the site comes back. Without the track
            // an almost-empty countdown is invisible on a black screen.
            dc.setColor(Theme.nodeDim(area.id), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x - Layout.s(11), y + Layout.s(6), Layout.s(22), Layout.s(9));
            Theme.ring(dc, x, y, Layout.s(24), Layout.s(3), 1.0, Theme.PANEL_HI);
            Theme.ring(dc, x, y, Layout.s(24), Layout.s(3), node.regrowth(),
                Theme.nodeMain(area.id));
            return;
        }

        var full = node.fullness();
        var kind = area.nodeKind();
        if (kind == 0) {
            drawTree(dc, x, y, full);
        } else if (kind == 1) {
            drawBoulder(dc, x, y, full);
        } else if (kind == 2) {
            drawSeam(dc, x, y, full);
        } else {
            drawFlax(dc, x, y, full);
        }
    }

    private function drawTree(dc as Dc, x as Number, y as Number, full as Float) as Void {
        var spread = Layout.s((14 + 16 * full).toNumber());
        var height = Layout.s((16 + 20 * full).toNumber());
        dc.setColor(Theme.WOOD, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - Layout.s(4), y + Layout.s(8), Layout.s(8), Layout.s(16));
        dc.setColor(Theme.nodeMain(Balance.FOREST), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x, y - height] as [Numeric, Numeric],
            [x - spread, y + Layout.s(10)] as [Numeric, Numeric],
            [x + spread, y + Layout.s(10)] as [Numeric, Numeric]
        ] as Array<[Numeric, Numeric]>);
        dc.setColor(Theme.nodeDim(Balance.FOREST), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x, y - height - Layout.s(10)] as [Numeric, Numeric],
            [x - spread * 2 / 3, y - Layout.s(4)] as [Numeric, Numeric],
            [x + spread * 2 / 3, y - Layout.s(4)] as [Numeric, Numeric]
        ] as Array<[Numeric, Numeric]>);
    }

    //! A boulder wears down: the same shape, smaller, on the shelf of cut
    //! stone it has already given up.
    private function drawBoulder(dc as Dc, x as Number, y as Number, full as Float) as Void {
        var r = Layout.s((10 + 18 * full).toNumber());
        dc.setColor(Theme.nodeDim(Balance.QUARRY), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - Layout.s(28), y + Layout.s(8), Layout.s(56), Layout.s(8));
        dc.setColor(Theme.nodeMain(Balance.QUARRY), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x - r, y + Layout.s(10)] as [Numeric, Numeric],
            [x - r * 2 / 3, y - r / 2] as [Numeric, Numeric],
            [x, y - r] as [Numeric, Numeric],
            [x + r * 3 / 4, y - r / 3] as [Numeric, Numeric],
            [x + r, y + Layout.s(10)] as [Numeric, Numeric]
        ] as Array<[Numeric, Numeric]>);
    }

    //! An ore seam: dead rock whose veins go out as it is worked.
    private function drawSeam(dc as Dc, x as Number, y as Number, full as Float) as Void {
        var r = Layout.s(22);
        dc.setColor(Theme.nodeDim(Balance.MINE), Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x - r, y + Layout.s(12)] as [Numeric, Numeric],
            [x - r * 3 / 4, y - r / 2] as [Numeric, Numeric],
            [x + r / 4, y - r] as [Numeric, Numeric],
            [x + r, y] as [Numeric, Numeric],
            [x + r * 3 / 4, y + Layout.s(12)] as [Numeric, Numeric]
        ] as Array<[Numeric, Numeric]>);

        var veins = (1 + 3 * full).toNumber();
        dc.setColor(Theme.nodeMain(Balance.MINE), Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < veins; i += 1) {
            var vy = y - r / 2 + i * Layout.s(9);
            dc.fillCircle(x - Layout.s(6) + (i % 2) * Layout.s(12), vy, Layout.s(4));
        }
    }

    //! A stand of flax, cut down one stalk at a time.
    private function drawFlax(dc as Dc, x as Number, y as Number, full as Float) as Void {
        var stalks = (2 + 5 * full).toNumber();
        var height = Layout.s(30);
        dc.setColor(Theme.nodeDim(Balance.FIELD), Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - Layout.s(20), y + Layout.s(12), Layout.s(40), Layout.s(5));
        dc.setColor(Theme.nodeMain(Balance.FIELD), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(Layout.s(3));
        for (var i = 0; i < stalks; i += 1) {
            var sx = x - Layout.s(18) + i * Layout.s(6);
            var lean = (i % 2 == 0) ? Layout.s(3) : -Layout.s(3);
            dc.drawLine(sx, y + Layout.s(12), sx + lean, y + Layout.s(12) - height);
            dc.fillCircle(sx + lean, y + Layout.s(12) - height, Layout.s(3));
        }
        dc.setPenWidth(1);
    }

    private function drawStorage(dc as Dc, area as Area) as Void {
        var x = Layout.s(area.storageX.toNumber());
        var y = Layout.s(area.storageY.toNumber());
        var w = Layout.s(38);
        var h = Layout.s(26);

        dc.setColor(Theme.STORAGE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - w / 2, y - h / 2, w, h);
        dc.fillPolygon([
            [x - w / 2 - Layout.s(4), y - h / 2] as [Numeric, Numeric],
            [x, y - h / 2 - Layout.s(14)] as [Numeric, Numeric],
            [x + w / 2 + Layout.s(4), y - h / 2] as [Numeric, Numeric]
        ] as Array<[Numeric, Numeric]>);

        dc.setColor(Theme.nodeMain(area.id), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + h / 2 + Layout.s(2), Graphics.FONT_XTINY,
            area.stock.toNumber().toString(), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawMachine(dc as Dc, area as Area) as Void {
        var x = Layout.s(area.machineX.toNumber());
        var y = Layout.s(area.machineY.toNumber());
        var w = Layout.s(38);
        var h = Layout.s(30);
        var machine = area.machine;

        dc.setColor(machine.isBuilt() ? Theme.machineColor(area.id) : Theme.PANEL_HI,
            Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - w / 2, y - h / 2, w, h);
        dc.fillRectangle(x + Layout.s(6), y - h / 2 - Layout.s(10), Layout.s(9),
            Layout.s(10));

        if (!machine.isBuilt()) {
            dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + h / 2 + Layout.s(2), Graphics.FONT_XTINY, "BUILD",
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        Theme.bar(dc, x - w / 2, y + h / 2 + Layout.s(4), w, Layout.s(6),
            machine.batchProgress(), Theme.CASH, Theme.PANEL_HI);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + h / 2 + Layout.s(12), Graphics.FONT_XTINY,
            "Lv " + machine.level.toString(), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawActor(dc as Dc, actor as Actor, radius as Number,
                               color as Number) as Void {
        var x = Layout.s(actor.x.toNumber());
        var y = Layout.s(actor.y.toNumber());

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, radius);

        // How full the pack is, as a ring around whoever is carrying it. The
        // player never has to read an inventory screen to know to head home.
        if (actor.carry > 0.0) {
            Theme.ring(dc, x, y, radius + Layout.s(5), Layout.s(3),
                actor.fillFraction(), Theme.WOOD);
        }
        if (actor.state == ActorState.COLLECT) {
            dc.setColor(Theme.WOOD, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + radius, y - radius, Layout.s(3), Layout.s(10));
        }
    }

    //! The card over a locked area: what it is, and what it costs to open.
    private function drawLockCard(dc as Dc, area as Area) as Void {
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(146), Graphics.FONT_MEDIUM, area.name(),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(192), Graphics.FONT_XTINY,
            area.resourceName() + " into " + area.machine.product(),
            Graphics.TEXT_JUSTIFY_CENTER);
        Theme.bigCash(dc, Layout.cx, Layout.s(218), area.unlockCost(), Theme.CASH,
            Graphics.FONT_NUMBER_MILD);
    }

    //! One dot per area along the bottom of the clearing, so it is obvious
    //! there is more of the world to swipe to.
    private function drawAreaDots(dc as Dc, game as GameState) as Void {
        var spacing = Layout.s(18);
        var y = Layout.s(306);
        var left = Layout.cx - spacing * (Balance.AREA_COUNT - 1) / 2;
        for (var i = 0; i < game.areas.size(); i += 1) {
            var colour = Theme.PANEL_HI;
            if (i == game.current) {
                colour = Theme.CASH;
            } else if (game.areas[i].unlocked) {
                colour = Theme.CASH_DIM;
            }
            dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(left + i * spacing, y, Layout.s(4));
        }
    }

    private function drawAreaLabel(dc as Dc, area as Area) as Void {
        if (mLabelLeft <= 0.0) {
            return;
        }
        dc.setColor(Theme.TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(82), Graphics.FONT_SMALL, area.name(),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawToast(dc as Dc) as Void {
        if (mToastLeft <= 0.0) {
            return;
        }
        // Rises as it fades, so two sales in a row do not overlap.
        var lift = Layout.s(((mToastFor - mToastLeft) / mToastFor * 25).toNumber());
        dc.setColor(Theme.CASH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(236) - lift, Graphics.FONT_SMALL, mToast,
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawButton(dc as Dc, game as GameState, area as Area) as Void {
        var what = action();
        var label = "COLLECT";
        var fill = Theme.PANEL_HI;
        var text = Theme.TEXT;

        if (what == ACT_UNLOCK) {
            var afford = game.cash >= area.unlockCost();
            label = "UNLOCK";
            fill = afford ? Theme.CASH_DIM : Theme.PANEL;
            text = afford ? Theme.TEXT : Theme.TEXT_DIM;
        } else if (what == ACT_RICH) {
            label = "RICH VEIN";
            fill = Theme.WORKER;
            text = Theme.BG;
        } else if (what == ACT_STORE) {
            label = "STORE";
        } else if (what == ACT_SELL) {
            label = "SELL " + Fmt.cash(area.stockValue());
            fill = Theme.CASH_DIM;
        } else if (area.bestNode(game.player.x, game.player.y) < 0) {
            label = "REGROWING";
            fill = Theme.PANEL;
            text = Theme.TEXT_DIM;
        }

        Theme.button(dc, mBtnX, mBtnY, mBtnW, mBtnH, label, fill, text);
    }

    //! Device pixels back to the board's 416-wide design space.
    private function unscale(value as Number) as Number {
        return (value / Layout.scale).toNumber();
    }
}
