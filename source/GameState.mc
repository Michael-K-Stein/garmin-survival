import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;

//! The whole simulation: four areas, the player who walks around one of them
//! at a time, the single wallet they all feed, and the save file. Views never
//! write these fields directly - they call the command and buy helpers below,
//! so every invariant lives in one place.
class GameState {

    //! Bumped whenever the save layout changes incompatibly.
    private const SAVE_VERSION = 2;
    private const SAVE_KEY = "timberline";

    // --- Persistent ------------------------------------------------------
    public var cash as Double = 0.0d;
    public var lifetime as Double = 0.0d;

    public var lvlSpeed as Number = 0;
    public var lvlCapacity as Number = 0;
    public var lvlCollect as Number = 0;
    public var lvlRegrow as Number = 0;

    //! Crew upgrades are bought once and apply to every area, because per-
    //! worker configuration is exactly the fiddling this game is avoiding.
    public var lvlWorkerSpeed as Number = 0;
    public var lvlWorkerCapacity as Number = 0;

    public var haptics as Boolean = true;
    public var lastSeen as Number = 0;

    // --- The world -------------------------------------------------------
    public var areas as Array<Area>;
    public var current as Number = Balance.FOREST;
    public var player as Actor;

    // --- Waiting to be claimed ------------------------------------------
    public var offlineCash as Double = 0.0d;
    public var offlineUnits as Float = 0.0;
    public var offlineSecs as Number = 0;

    private var mLastTickMs as Number = 0;
    private var mSinceSaveSecs as Float = 0.0;

    function initialize() {
        areas = new [Balance.AREA_COUNT] as Array<Area>;
        for (var i = 0; i < Balance.AREA_COUNT; i += 1) {
            areas[i] = new Area(i);
        }
        var start = Balance.PLAYER_START as Array<Number>;
        player = new Actor(start[0].toFloat(), start[1].toFloat(), false);
        mLastTickMs = System.getTimer();
    }

    function area() as Area {
        return areas[current];
    }

    // ------------------------------------------------------------ stat curves

    function playerSpeed() as Float {
        return Balance.PLAYER_SPEED * (1.0 + Balance.PLAYER_SPEED_STEP * lvlSpeed);
    }

    function playerCapacity() as Number {
        return Balance.PLAYER_CAPACITY + Balance.PLAYER_CAPACITY_STEP * lvlCapacity;
    }

    function playerCollect() as Float {
        return Balance.PLAYER_COLLECT * (1.0 + Balance.PLAYER_COLLECT_STEP * lvlCollect);
    }

    //! Node regrowth speed multiplier: 1.0 at level 0, faster from there.
    function regrowBoost() as Float {
        return 1.0 + Balance.PLAYER_REGROW_STEP * lvlRegrow;
    }

    function workerSpeed() as Float {
        return Balance.WORKER_SPEED * (1.0 + Balance.WORKER_SPEED_STEP * lvlWorkerSpeed);
    }

    function workerCapacity() as Number {
        return Balance.WORKER_CAPACITY + Balance.WORKER_CAPACITY_STEP * lvlWorkerCapacity;
    }

    //! A faster crew swings faster too, so one upgrade is one decision.
    function workerCollect() as Float {
        return Balance.WORKER_COLLECT * (1.0 + Balance.WORKER_COLLECT_STEP * lvlWorkerSpeed);
    }

    //! Everyone on the payroll, across every area.
    function payroll() as Number {
        var total = 0;
        for (var i = 0; i < areas.size(); i += 1) {
            total += areas[i].workers();
        }
        return total;
    }

    // ------------------------------------------------------------------ costs

    private function curve(base as Float, level as Number, growth as Float) as Double {
        return base * Math.pow(growth, level).toDouble();
    }

    function costSpeed() as Double {
        return curve(Balance.COST_SPEED, lvlSpeed, Balance.COST_GROWTH);
    }

    function costCapacity() as Double {
        return curve(Balance.COST_CAPACITY, lvlCapacity, Balance.COST_GROWTH);
    }

    function costCollect() as Double {
        return curve(Balance.COST_COLLECT, lvlCollect, Balance.COST_GROWTH);
    }

    function costRegrow() as Double {
        return curve(Balance.COST_REGROW, lvlRegrow, Balance.COST_GROWTH);
    }

    //! Priced off the whole payroll, so a fifth area starts out expensive to
    //! staff even though its first hire is nobody's first hire.
    function costHire() as Double {
        return curve(Balance.COST_HIRE, payroll(), Balance.HIRE_GROWTH);
    }

    function costWorkerSpeed() as Double {
        return curve(Balance.COST_WORKER_SPEED, lvlWorkerSpeed, Balance.COST_GROWTH);
    }

    function costWorkerCapacity() as Double {
        return curve(Balance.COST_WORKER_CAPACITY, lvlWorkerCapacity, Balance.COST_GROWTH);
    }

    // --------------------------------------------------------------- purchases

    private function spend(amount as Double) as Boolean {
        if (cash < amount) {
            return false;
        }
        cash -= amount;
        Events.emit(Events.CASH_CHANGED, cash);
        return true;
    }

    function buySpeed() as Boolean {
        if (!spend(costSpeed())) {
            return false;
        }
        lvlSpeed += 1;
        Events.emit(Events.UPGRADE_PURCHASED, lvlSpeed.toDouble());
        return true;
    }

    function buyCapacity() as Boolean {
        if (!spend(costCapacity())) {
            return false;
        }
        lvlCapacity += 1;
        Events.emit(Events.UPGRADE_PURCHASED, lvlCapacity.toDouble());
        return true;
    }

    function buyCollect() as Boolean {
        if (!spend(costCollect())) {
            return false;
        }
        lvlCollect += 1;
        Events.emit(Events.UPGRADE_PURCHASED, lvlCollect.toDouble());
        return true;
    }

    function buyRegrow() as Boolean {
        if (!spend(costRegrow())) {
            return false;
        }
        lvlRegrow += 1;
        Events.emit(Events.UPGRADE_PURCHASED, lvlRegrow.toDouble());
        return true;
    }

    //! Hire into the area currently on screen; that tap is the whole of the
    //! game's worker assignment.
    function hireWorker() as Boolean {
        var here = area();
        if (!here.canHire() || !spend(costHire())) {
            return false;
        }
        here.crew.add(new Actor(here.storageX, here.storageY, true));
        Events.emit(Events.WORKER_HIRED, here.workers().toDouble());
        return true;
    }

    function buyWorkerSpeed() as Boolean {
        if (!spend(costWorkerSpeed())) {
            return false;
        }
        lvlWorkerSpeed += 1;
        Events.emit(Events.UPGRADE_PURCHASED, lvlWorkerSpeed.toDouble());
        return true;
    }

    function buyWorkerCapacity() as Boolean {
        if (!spend(costWorkerCapacity())) {
            return false;
        }
        lvlWorkerCapacity += 1;
        Events.emit(Events.UPGRADE_PURCHASED, lvlWorkerCapacity.toDouble());
        return true;
    }

    function upgradeMachine() as Boolean {
        var machine = area().machine;
        if (!spend(machine.upgradeCost())) {
            return false;
        }
        machine.level += 1;
        Events.emit(Events.UPGRADE_PURCHASED, machine.level.toDouble());
        return true;
    }

    // -------------------------------------------------------------------- map

    //! Swipe to the next or previous board. Locked areas are still shown -
    //! seeing the price is what makes it a goal - so this always moves.
    function switchArea(delta as Number) as Void {
        var next = (current + delta + Balance.AREA_COUNT) % Balance.AREA_COUNT;
        if (next == current) {
            return;
        }
        // Whatever the player was carrying belongs to the yard they left.
        if (player.carry > 0.0) {
            area().deposit(player.carry);
            player.carry = 0.0;
        }
        current = next;
        var start = Balance.PLAYER_START as Array<Number>;
        player.x = start[0].toFloat();
        player.y = start[1].toFloat();
        player.target = -1;
        player.state = ActorState.IDLE;
    }

    function unlockArea() as Boolean {
        var here = area();
        if (here.unlocked || !spend(here.unlockCost())) {
            return false;
        }
        here.unlocked = true;
        Events.emit(Events.AREA_UNLOCKED, here.id.toDouble());
        return true;
    }

    // ---------------------------------------------------------------- economy

    private function earn(amount as Double) as Void {
        cash += amount;
        lifetime += amount;
        Events.emit(Events.CASH_CHANGED, cash);
    }

    //! Sell the current yard at the raw price. Returns the cash taken, so the
    //! view can float a number over the hut.
    function sellStock() as Double {
        var here = area();
        var value = here.stockValue();
        if (value <= 0.0d) {
            return 0.0d;
        }
        here.stock = 0.0;
        earn(value);
        Events.emit(Events.ITEM_SOLD, value);
        return value;
    }

    //! Hands-off income from every unlocked board, in cash per minute.
    function incomePerMinute() as Double {
        var speed = workerSpeed();
        var capacity = workerCapacity();
        var collect = workerCollect();
        var total = 0.0d;
        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            if (board.unlocked) {
                total += board.incomePerMinute(speed, capacity, collect);
            }
        }
        return total;
    }

    // -------------------------------------------------------------- simulation

    //! Advance everything by wall-clock time, so the result does not depend
    //! on how often the active view happens to redraw.
    //!
    //! Every unlocked area is stepped, not just the one on screen: a crew you
    //! walked away from is the whole point of having hired them.
    function tick() as Void {
        var now = System.getTimer();
        var dtMs = now - mLastTickMs;
        mLastTickMs = now;

        // System.getTimer() wraps roughly every 25 days; a negative or absurd
        // delta means we lost track, so charge nothing for it.
        if (dtMs <= 0 || dtMs > 5000) {
            return;
        }
        var dt = dtMs / 1000.0;

        var speed = workerSpeed();
        var capacity = workerCapacity();
        var collect = workerCollect();
        var boost = regrowBoost();
        var earned = 0.0d;
        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            if (board.unlocked) {
                earned += board.tick(dt, speed, capacity, collect, boost);
            }
        }
        if (earned > 0.0d) {
            earn(earned);
        }

        player.setStats(playerSpeed(), playerCapacity(), playerCollect());
        player.tick(dt, area());

        mSinceSaveSecs += dt;
        if (mSinceSaveSecs >= Balance.AUTOSAVE_SECS) {
            mSinceSaveSecs = 0.0;
            save();
        }
    }

    //! Move the pending offline pile into the wallet. The material half has
    //! already been credited to the yards it belongs to.
    function claimOffline() as Void {
        if (offlineCash > 0.0d) {
            earn(offlineCash);
        }
        offlineCash = 0.0d;
        offlineUnits = 0.0;
        offlineSecs = 0;
    }

    function hasOffline() as Boolean {
        return offlineCash > 0.0d || offlineUnits > 0.0;
    }

    // ------------------------------------------------------------ persistence

    function save() as Void {
        lastSeen = Time.now().value();

        var stocks = new [areas.size()] as Array<Double>;
        var machines = new [areas.size()] as Array<Number>;
        var batches = new [areas.size()] as Array<Double>;
        var made = new [areas.size()] as Array<Number>;
        var hired = new [areas.size()] as Array<Number>;
        var open = new [areas.size()] as Array<Number>;
        var left = new [areas.size() * Balance.NODES.size()] as Array<Number>;
        var regrow = new [areas.size() * Balance.NODES.size()] as Array<Number>;

        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            stocks[i] = board.stock.toDouble();
            machines[i] = board.machine.level;
            batches[i] = board.machine.batch.toDouble();
            made[i] = board.machine.made;
            hired[i] = board.workers();
            open[i] = board.unlocked ? 1 : 0;
            for (var n = 0; n < board.nodes.size(); n += 1) {
                var slot = i * board.nodes.size() + n;
                left[slot] = board.nodes[n].quantity.toNumber();
                regrow[slot] = board.nodes[n].regrowLeft().toNumber();
            }
        }

        var data = {
            "v" => SAVE_VERSION,
            "cash" => cash,
            "life" => lifetime,
            "spd" => lvlSpeed,
            "cap" => lvlCapacity,
            "col" => lvlCollect,
            "reg" => lvlRegrow,
            "wspd" => lvlWorkerSpeed,
            "wcap" => lvlWorkerCapacity,
            "area" => current,
            "stock" => stocks,
            "mach" => machines,
            "batch" => batches,
            "made" => made,
            "crew" => hired,
            "open" => open,
            "left" => left,
            "regrow" => regrow,
            "haptics" => haptics,
            "seen" => lastSeen
        };
        try {
            Application.Storage.setValue(SAVE_KEY, data);
        } catch (ex) {
            // A full storage partition must never take the game down.
            System.println("save failed");
        }
    }

    function load() as Void {
        mLastTickMs = System.getTimer();
        var raw = null;
        try {
            raw = Application.Storage.getValue(SAVE_KEY);
        } catch (ex) {
            raw = null;
        }
        if (!(raw instanceof Lang.Dictionary)) {
            return;
        }
        var data = raw as Dictionary;
        // Saves from an older layout are dropped rather than guessed at.
        if (readNumber(data, "v", 0) != SAVE_VERSION) {
            return;
        }

        cash = readDouble(data, "cash", 0.0d);
        lifetime = readDouble(data, "life", 0.0d);
        lvlSpeed = readNumber(data, "spd", 0);
        lvlCapacity = readNumber(data, "cap", 0);
        lvlCollect = readNumber(data, "col", 0);
        lvlRegrow = readNumber(data, "reg", 0);
        lvlWorkerSpeed = readNumber(data, "wspd", 0);
        lvlWorkerCapacity = readNumber(data, "wcap", 0);
        lastSeen = readNumber(data, "seen", 0);

        var flag = data["haptics"];
        haptics = (flag instanceof Lang.Boolean) ? flag : true;

        var stocks = numbers(data, "stock");
        var machines = numbers(data, "mach");
        var batches = numbers(data, "batch");
        var made = numbers(data, "made");
        var hired = numbers(data, "crew");
        var open = numbers(data, "open");
        var left = numbers(data, "left");
        var regrow = numbers(data, "regrow");

        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            board.stock = at(stocks, i, 0.0);
            board.machine.level = at(machines, i, 0.0).toNumber();
            board.machine.batch = at(batches, i, 0.0);
            board.machine.made = at(made, i, 0.0).toNumber();
            board.unlocked = (i == Balance.FOREST) || at(open, i, 0.0) > 0.5;

            var want = at(hired, i, 0.0).toNumber();
            if (want > Balance.WORKER_MAX) {
                want = Balance.WORKER_MAX;
            }
            board.crew = [] as Array<Actor>;
            for (var w = 0; w < want; w += 1) {
                board.crew.add(new Actor(board.storageX, board.storageY, true));
            }

            for (var n = 0; n < board.nodes.size(); n += 1) {
                var slot = i * board.nodes.size() + n;
                board.nodes[n].restore(at(left, slot, board.nodes[n].maxQuantity.toFloat()),
                    at(regrow, slot, 0.0));
            }
        }

        var where = readNumber(data, "area", Balance.FOREST);
        current = (where >= 0 && where < areas.size()) ? where : Balance.FOREST;

        computeOffline();
    }

    //! Work out what every crew and machine got through while the app was
    //! closed. Nothing is simulated step by step: each crew produces at its
    //! cycle rate, each machine eats as much of that as its throughput
    //! allows, and the remainder lands in that area's yard as raw material.
    private function computeOffline() as Void {
        offlineCash = 0.0d;
        offlineUnits = 0.0;
        offlineSecs = 0;
        if (lastSeen <= 0) {
            return;
        }
        var elapsed = Time.now().value() - lastSeen;
        if (elapsed < Balance.MIN_OFFLINE_SECS) {
            return;
        }
        if (elapsed > Balance.MAX_OFFLINE_SECS) {
            elapsed = Balance.MAX_OFFLINE_SECS;
        }

        var speed = workerSpeed();
        var capacity = workerCapacity();
        var collect = workerCollect();

        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            if (!board.unlocked) {
                continue;
            }
            var gathered = board.crewRate(speed, capacity, collect) * elapsed
                * Balance.OFFLINE_EFFICIENCY;
            var available = gathered + board.stock;
            var processed = board.machine.rate() * elapsed;
            if (processed > available) {
                processed = available;
            }
            if (processed > 0.0) {
                offlineCash += board.machine.valueOf(processed);
                board.machine.absorb(processed);
                // The machine ate the yard first; the rest came off the pile
                // the crew brought in.
                var fromYard = (processed < board.stock) ? processed : board.stock;
                board.stock -= fromYard;
                gathered -= (processed - fromYard);
            }
            if (gathered > 0.0) {
                board.stock += gathered;
                offlineUnits += gathered;
            }
        }

        if (offlineCash > 0.0d || offlineUnits > 0.0) {
            offlineSecs = elapsed;
        }
    }

    function wipe() as Void {
        cash = 0.0d;
        lifetime = 0.0d;
        lvlSpeed = 0;
        lvlCapacity = 0;
        lvlCollect = 0;
        lvlRegrow = 0;
        lvlWorkerSpeed = 0;
        lvlWorkerCapacity = 0;
        current = Balance.FOREST;
        offlineCash = 0.0d;
        offlineUnits = 0.0;
        offlineSecs = 0;
        areas = new [Balance.AREA_COUNT] as Array<Area>;
        for (var i = 0; i < Balance.AREA_COUNT; i += 1) {
            areas[i] = new Area(i);
        }
        var start = Balance.PLAYER_START as Array<Number>;
        player = new Actor(start[0].toFloat(), start[1].toFloat(), false);
        Application.Storage.deleteValue(SAVE_KEY);
        save();
    }

    // ---------------------------------------------------------------- helpers

    private function readNumber(data as Dictionary, key as String, fallback as Number) as Number {
        var value = data[key];
        return (value instanceof Lang.Number) ? value : fallback;
    }

    private function readDouble(data as Dictionary, key as String, fallback as Double) as Double {
        var value = data[key];
        if (value instanceof Lang.Double || value instanceof Lang.Float
                || value instanceof Lang.Number || value instanceof Lang.Long) {
            var d = value.toDouble();
            return (d >= 0.0d) ? d : fallback;
        }
        return fallback;
    }

    //! A saved array read back as plain floats, or null if it is missing or
    //! is not an array at all.
    private function numbers(data as Dictionary, key as String) as Array<Float> or Null {
        var value = data[key];
        if (!(value instanceof Lang.Array)) {
            return null;
        }
        var list = value as Array;
        var out = new [list.size()] as Array<Float>;
        for (var i = 0; i < list.size(); i += 1) {
            var item = list[i];
            out[i] = (item instanceof Lang.Number || item instanceof Lang.Float
                || item instanceof Lang.Double || item instanceof Lang.Long)
                ? item.toFloat() : 0.0;
        }
        return out;
    }

    private function at(list as Array<Float> or Null, index as Number,
                        fallback as Float) as Float {
        if (list == null || index < 0 || index >= list.size()) {
            return fallback;
        }
        return list[index];
    }
}
