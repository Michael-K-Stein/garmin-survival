import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The four management pages, swiped between left and right.
module Page {
    const PLAYER = 0;
    const CREW = 1;
    const MACHINE = 2;
    const OPTIONS = 3;
    const COUNT = 4;
}

//! Everything you spend money on. One page per category, at most three rows
//! per page, every row a 72px slab you can hit without looking.
class ManageView extends WatchUi.View {

    private var mGame as GameState or Null = null;
    private var mPage as Number;

    // Row geometry in device pixels, recomputed on layout.
    private var mRowY as Array<Number> = [] as Array<Number>;
    private var mRowX as Array<Number> = [] as Array<Number>;
    private var mRowW as Array<Number> = [] as Array<Number>;
    private var mRowH as Number = 0;

    //! Rows on the current page: [title, detail, cost, enabled].
    private var mRows as Array<Array<Object> > = [] as Array<Array<Object> >;

    function initialize(page as Number) {
        View.initialize();
        mPage = page;
    }

    function onLayout(dc as Dc) as Void {
        Layout.measure(dc);
        mRowH = Layout.s(72);
        var tops = [Layout.s(70), Layout.s(148), Layout.s(226)] as Array<Number>;
        mRowY = tops;
        mRowX = new [tops.size()] as Array<Number>;
        mRowW = new [tops.size()] as Array<Number>;
        for (var i = 0; i < tops.size(); i += 1) {
            var row = Layout.fitRow(tops[i], mRowH, Layout.s(10));
            mRowX[i] = row[0];
            mRowW[i] = row[1];
        }
    }

    function onShow() as Void {
        mGame = TimberlineApp.game();
    }

    function turnPage(delta as Number) as Void {
        mPage = (mPage + delta + Page.COUNT) % Page.COUNT;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------------ input

    //! A tap in device pixels. Returns true if it bought something.
    function onTapAt(px as Number, py as Number) as Boolean {
        for (var i = 0; i < mRows.size() && i < mRowY.size(); i += 1) {
            var y = mRowY[i];
            if (py < y || py > y + mRowH || px < mRowX[i] || px > mRowX[i] + mRowW[i]) {
                continue;
            }
            return buy(i);
        }
        return false;
    }

    private function buy(index as Number) as Boolean {
        var game = mGame;
        if (game == null) {
            return false;
        }
        var done = false;
        if (mPage == Page.PLAYER) {
            if (index == 0) {
                done = game.buySpeed();
            } else if (index == 1) {
                done = game.buyCapacity();
            } else {
                done = game.buyCollect();
            }
        } else if (mPage == Page.CREW) {
            if (index == 0) {
                done = game.hireWorker();
            } else if (index == 1) {
                done = game.buyWorkerSpeed();
            } else {
                done = game.buyWorkerCapacity();
            }
        } else if (mPage == Page.OPTIONS) {
            return option(game, index);
        } else if (index == 0) {
            done = game.upgradeMachine();
        }

        if (done) {
            Haptics.confirm();
            game.save();
        } else {
            Haptics.deny();
        }
        WatchUi.requestUpdate();
        return done;
    }

    //! The options rows do not spend money, so they answer for themselves.
    private function option(game as GameState, index as Number) as Boolean {
        if (index == 0) {
            game.haptics = !game.haptics;
            game.save();
            if (game.haptics) {
                Haptics.confirm();
            }
            WatchUi.requestUpdate();
            return true;
        }
        // Erasing a save is the one thing here worth a second question.
        WatchUi.pushView(
            new WatchUi.Confirmation("Wipe save?"),
            new WipeDelegate(),
            WatchUi.SLIDE_UP);
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
        mRows = rowsFor(game);

        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(34), Graphics.FONT_XTINY, title(),
            Graphics.TEXT_JUSTIFY_CENTER);

        for (var i = 0; i < mRows.size() && i < mRowY.size(); i += 1) {
            drawRow(dc, i, mRows[i]);
        }

        if (mPage == Page.MACHINE) {
            drawMachineDetail(dc, game);
        }

        dc.setColor(Theme.CASH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, Layout.s(304), Graphics.FONT_TINY,
            Fmt.cash(game.cash), Graphics.TEXT_JUSTIFY_CENTER);
        drawPageDots(dc);
    }

    //! Crew and machinery are bought for the board you are standing on, so
    //! the title says which one that is.
    private function title() as String {
        var game = mGame;
        if (mPage == Page.PLAYER || game == null) {
            return "YOU";
        }
        if (mPage == Page.CREW) {
            return "CREW - " + game.area().name();
        }
        if (mPage == Page.OPTIONS) {
            return "OPTIONS";
        }
        return game.area().machine.name();
    }

    //! Build the current page's rows. Cost is a Double; enabled is a Boolean.
    private function rowsFor(game as GameState) as Array<Array<Object> > {
        if (mPage == Page.PLAYER) {
            return [
                row("SPEED", "Lv " + game.lvlSpeed.toString(), game.costSpeed(), game),
                row("CARRY", game.playerCapacity().toString() + " units",
                    game.costCapacity(), game),
                row("GATHER", Fmt.rate(game.playerCollect().toDouble()) + "/s",
                    game.costCollect(), game)
            ] as Array<Array<Object> >;
        }

        var here = game.area();
        if (mPage == Page.CREW) {
            var hire = here.canHire()
                ? row("HIRE", here.workers().toString() + " / "
                    + Balance.WORKER_MAX.toString(), game.costHire(), game)
                : ["HIRE", "this area is full", 0.0d, false] as Array<Object>;
            return [
                hire,
                row("SPEED", "Lv " + game.lvlWorkerSpeed.toString(),
                    game.costWorkerSpeed(), game),
                row("CARRY", game.workerCapacity().toString() + " units",
                    game.costWorkerCapacity(), game)
            ] as Array<Array<Object> >;
        }

        if (mPage == Page.OPTIONS) {
            // Free rows: the cost column is empty and the slab is always live.
            return [
                ["HAPTICS", game.haptics ? "on" : "off", 0.0d, true] as Array<Object>,
                ["WIPE SAVE", "erase everything", 0.0d, true] as Array<Object>
            ] as Array<Array<Object> >;
        }

        var machine = here.machine;
        var label = machine.isBuilt() ? "UPGRADE" : "BUILD";
        var detail = machine.isBuilt()
            ? "Lv " + machine.level.toString()
            : here.resourceName() + " into " + machine.product();
        return [row(label, detail, machine.upgradeCost(), game)] as Array<Array<Object> >;
    }

    private function row(label as String, detail as String, cost as Double,
                         game as GameState) as Array<Object> {
        return [label, detail, cost, game.cash >= cost] as Array<Object>;
    }

    private function drawRow(dc as Dc, index as Number, data as Array<Object>) as Void {
        var x = mRowX[index];
        var y = mRowY[index];
        var w = mRowW[index];
        var enabled = data[3] as Boolean;
        var cost = data[2] as Double;

        Theme.panel(dc, x, y, w, mRowH, Layout.s(16),
            enabled ? Theme.PANEL_HI : Theme.PANEL,
            enabled ? Theme.CASH_DIM : null);

        var pad = Layout.s(18);
        dc.setColor(enabled ? Theme.TEXT : Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad, y + Layout.s(8), Graphics.FONT_TINY,
            data[0] as String, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + pad, y + Layout.s(38), Graphics.FONT_XTINY,
            data[1] as String, Graphics.TEXT_JUSTIFY_LEFT);

        if (cost > 0.0d) {
            dc.setColor(enabled ? Theme.CASH : Theme.BAD, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + w - pad, y + mRowH / 2, Graphics.FONT_TINY,
                Fmt.cash(cost),
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! The machine page has room to explain what the money is buying.
    private function drawMachineDetail(dc as Dc, game as GameState) as Void {
        var here = game.area();
        var machine = here.machine;
        var y = mRowY[1];
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        if (!machine.isBuilt()) {
            dc.drawText(Layout.cx, y, Graphics.FONT_XTINY,
                Balance.MACHINE_BATCH.toString() + " " + here.resourceName()
                + " becomes " + Balance.MACHINE_YIELD.toString() + " "
                + machine.product(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(Layout.cx, y + Layout.s(26), Graphics.FONT_XTINY,
                "and sells itself", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.drawText(Layout.cx, y, Graphics.FONT_XTINY,
            Fmt.rate(machine.rate().toDouble()) + " " + here.resourceName() + "/s in",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Theme.CASH, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(26), Graphics.FONT_TINY,
            "+" + Fmt.cash(machine.incomePerSecond() * 60.0d) + "/min",
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Theme.TEXT_DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(Layout.cx, y + Layout.s(58), Graphics.FONT_XTINY,
            machine.made.toString() + " " + machine.product() + " made",
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawPageDots(dc as Dc) as Void {
        var spacing = Layout.s(18);
        var y = Layout.s(356);
        var left = Layout.cx - spacing * (Page.COUNT - 1) / 2;
        for (var i = 0; i < Page.COUNT; i += 1) {
            dc.setColor(i == mPage ? Theme.CASH : Theme.PANEL_HI,
                Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(left + i * spacing, y, Layout.s(4));
        }
    }
}
