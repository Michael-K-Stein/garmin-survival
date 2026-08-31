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
    private const SAVE_VERSION = 3;
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

    //! Contracts are worked in order, so how many are finished is the whole
    //! of the state: it is both the completed set and the index of the open
    //! one.
    public var contractsDone as Number = 0;
    //! Legacy points, earned by moving camp. They never reset.
    public var legacy as Number = 0;

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

    //! Mastery levels across every area, which is the one number that says
    //! how well the whole valley is known.
    function masteryTotal() as Number {
        var total = 0;
        for (var i = 0; i < areas.size(); i += 1) {
            total += areas[i].mastery;
        }
        return total;
    }

    //! Machine levels across every area.
    function machineTotal() as Number {
        var total = 0;
        for (var i = 0; i < areas.size(); i += 1) {
            total += areas[i].machine.level;
        }
        return total;
    }

    function areasOpen() as Number {
        var total = 0;
        for (var i = 0; i < areas.size(); i += 1) {
            if (areas[i].unlocked) {
                total += 1;
            }
        }
        return total;
    }

    // -------------------------------------------------------------- contracts

    function contractCount() as Number {
        return (Balance.GOAL_NAME as Array<String>).size();
    }

    //! True once the last contract has been signed off.
    function contractsFinished() as Boolean {
        return contractsDone >= contractCount();
    }

    function contractName() as String {
        if (contractsFinished()) {
            return "ALL SIGNED OFF";
        }
        return (Balance.GOAL_NAME as Array<String>)[contractsDone];
    }

    function contractTarget() as Float {
        if (contractsFinished()) {
            return 1.0;
        }
        return (Balance.GOAL_TARGET as Array<Float>)[contractsDone];
    }

    function contractReward() as Double {
        if (contractsFinished()) {
            return 0.0d;
        }
        return (Balance.GOAL_REWARD as Array<Float>)[contractsDone].toDouble();
    }

    //! Where the open contract stands, in the same units as its target. Every
    //! kind reads state the game already keeps, so a contract costs nothing
    //! to track between checks.
    function contractProgress() as Float {
        if (contractsFinished()) {
            return 1.0;
        }
        var kind = (Balance.GOAL_KIND as Array<Number>)[contractsDone];
        if (kind == Balance.GOAL_LIFETIME) {
            return lifetime.toFloat();
        }
        if (kind == Balance.GOAL_CREW) {
            return payroll().toFloat();
        }
        if (kind == Balance.GOAL_MACHINE) {
            return machineTotal().toFloat();
        }
        if (kind == Balance.GOAL_AREAS) {
            return areasOpen().toFloat();
        }
        if (kind == Balance.GOAL_MASTERY) {
            return masteryTotal().toFloat();
        }
        if (kind == Balance.GOAL_GEAR) {
            return (lvlSpeed + lvlCapacity + lvlCollect + lvlRegrow).toFloat();
        }
        return legacy.toFloat();
    }

    //! Cash contracts are shown as money; the rest are plain counts.
    function contractIsCash() as Boolean {
        if (contractsFinished()) {
            return false;
        }
        return (Balance.GOAL_KIND as Array<Number>)[contractsDone]
            == Balance.GOAL_LIFETIME;
    }

    //! Sign off every contract whose target has been passed. More than one
    //! can fall at once - a big offline haul can carry two - so this loops.
    private function checkContracts() as Void {
        while (!contractsFinished() && contractProgress() >= contractTarget()) {
            var reward = contractReward();
            contractsDone += 1;
            Events.emit(Events.CONTRACT_DONE, reward);
            if (reward > 0.0d) {
                earn(reward);
            }
        }
    }

    // ----------------------------------------------------------------- legacy

    //! Everything earned is cut by this. One multiplier, applied at the one
    //! place money is created, so nothing can quietly escape it.
    function legacyBonus() as Float {
        return 1.0 + Balance.LEGACY_STEP * legacy;
    }

    //! What moving camp right now would pay. It is scored on this run's
    //! earnings alone, not on the career total - points already banked are
    //! kept, so what is being asked is only "was this camp worth leaving".
    //! Square-rooted, so a run has to be four times as big to be worth twice
    //! as much and there is no reward for bailing out early over and over.
    function prestigeGain() as Number {
        if (lifetime <= 0.0d) {
            return 0;
        }
        return Math.floor(Math.sqrt(lifetime / Balance.PRESTIGE_SCALE)).toNumber();
    }

    function canPrestige() as Boolean {
        return prestigeGain() > 0;
    }

    //! Lifetime this run needs before the next point lands, so the options
    //! page can say how far off it is rather than just "no".
    function prestigeNeeded() as Double {
        var next = prestigeGain() + 1;
        return (next * next).toDouble() * Balance.PRESTIGE_SCALE.toDouble();
    }

    //! Start the valley again. Cash, upgrades, crews, machines and unlocks
    //! all go; mastery, contracts and legacy are what you take with you.
    function prestige() as Boolean {
        var gain = prestigeGain();
        if (gain <= 0) {
            return false;
        }
        legacy += gain;

        var keptMastery = new [areas.size()] as Array<Number>;
        var keptCredit = new [areas.size()] as Array<Float>;
        for (var i = 0; i < areas.size(); i += 1) {
            keptMastery[i] = areas[i].mastery;
            keptCredit[i] = areas[i].credited;
        }

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
            areas[i].mastery = keptMastery[i];
            areas[i].credited = keptCredit[i];
            areas[i].syncMastery();
        }
        var start = Balance.PLAYER_START as Array<Number>;
        player = new Actor(start[0].toFloat(), start[1].toFloat(), false);

        Events.emit(Events.UPGRADE_PURCHASED, legacy.toDouble());
        save();
        return true;
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

    //! The one place money is created. Legacy is applied here rather than at
    //! each source, so no income path can be added later that quietly skips
    //! it. Returns what actually landed in the wallet.
    private function earn(amount as Double) as Double {
        var paid = amount * legacyBonus();
        cash += paid;
        lifetime += paid;
        Events.emit(Events.CASH_CHANGED, cash);
        return paid;
    }

    //! Sell the current yard at the raw price. Returns the cash taken, so the
    //! view can float a number over the hut.
    function sellStock() as Double {
        var here = area();
        var value = here.stockValue();
        if (value <= 0.0d) {
            return 0.0d;
        }
        var units = here.stock;
        here.stock = 0.0;
        var paid = earn(value);
        // Selling raw still teaches you the ground.
        here.credit(units);
        Events.emit(Events.ITEM_SOLD, paid);
        return paid;
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
        return total * legacyBonus();
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
                earned += board.tick(dt, speed, capacity, collect, boost,
                    i == current);
            }
        }
        if (earned > 0.0d) {
            earn(earned);
        }

        player.setStats(playerSpeed(), playerCapacity(), playerCollect());
        player.tick(dt, area());

        checkContracts();

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
        checkContracts();
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
        var mastered = new [areas.size()] as Array<Number>;
        var credited = new [areas.size()] as Array<Double>;
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
            mastered[i] = board.mastery;
            credited[i] = board.credited.toDouble();
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
            "mast" => mastered,
            "mcred" => credited,
            "goals" => contractsDone,
            "legacy" => legacy,
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
        contractsDone = readNumber(data, "goals", 0);
        if (contractsDone < 0 || contractsDone > contractCount()) {
            contractsDone = 0;
        }
        legacy = readNumber(data, "legacy", 0);
        if (legacy < 0) {
            legacy = 0;
        }

        var flag = data["haptics"];
        haptics = (flag instanceof Lang.Boolean) ? flag : true;

        var stocks = numbers(data, "stock");
        var machines = numbers(data, "mach");
        var batches = numbers(data, "batch");
        var made = numbers(data, "made");
        var hired = numbers(data, "crew");
        var open = numbers(data, "open");
        var mastered = numbers(data, "mast");
        var credited = numbers(data, "mcred");
        var left = numbers(data, "left");
        var regrow = numbers(data, "regrow");

        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            board.stock = at(stocks, i, 0.0);
            board.machine.level = at(machines, i, 0.0).toNumber();
            board.machine.batch = at(batches, i, 0.0);
            board.machine.made = at(made, i, 0.0).toNumber();
            board.unlocked = (i == Balance.FOREST) || at(open, i, 0.0) > 0.5;

            var level = at(mastered, i, 0.0).toNumber();
            board.mastery = (level > 0) ? level : 0;
            var banked = at(credited, i, 0.0);
            board.credited = (banked > 0.0) ? banked : 0.0;
            board.syncMastery();

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
        var boost = regrowBoost();

        for (var i = 0; i < areas.size(); i += 1) {
            var board = areas[i];
            if (!board.unlocked) {
                continue;
            }
            var gathered = board.crewRate(speed, capacity, collect) * elapsed
                * Balance.OFFLINE_EFFICIENCY;
            // A crew's demand is uncapped, but the nodes they draw from are
            // not - offline income must respect the same ceiling onscreen
            // play does, or leaving the app idle out-earns playing it.
            var sustained = board.nodeSupplyRate(boost) * elapsed;
            if (gathered > sustained) {
                gathered = sustained;
            }
            var available = gathered + board.stock;
            var processed = board.machine.rate() * elapsed;
            if (processed > available) {
                processed = available;
            }
            if (processed > 0.0) {
                offlineCash += board.machine.valueOf(processed);
                board.machine.absorb(processed);
                board.credit(processed);
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
