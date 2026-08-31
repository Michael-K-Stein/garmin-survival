import Toybox.Lang;
import Toybox.Math;

//! One compact board: its nodes, its yard, its machine and its crew. Areas
//! are self-contained, which is what lets the offline maths run over all four
//! of them without simulating a single footstep, and what keeps a swipe
//! between them a pure change of which one is drawn.
//!
//! Cash is deliberately not here. There is one wallet for the whole
//! operation, and it lives in GameState.
class Area {

    public var id as Number;
    public var unlocked as Boolean;

    public var nodes as Array<ResourceNode>;
    public var machine as Machine;
    //! Everyone hired to work this board. The player is not one of them.
    public var crew as Array<Actor>;
    //! Raw material sitting in the yard: sellable by hand, or machine feed.
    public var stock as Float = 0.0;

    //! How well this ground is known. Mastery is earned by realising units
    //! here - sold raw or run through the machine - and is a permanent
    //! multiplier on what everything from this area fetches.
    public var mastery as Number = 0;
    //! Units banked toward the next mastery level.
    public var credited as Float = 0.0;

    //! The site currently coming in rich, or -1. Rich veins only ever appear
    //! on the board the player is standing on, and only the player's own
    //! swings are worth more for them.
    public var richNode as Number = -1;
    private var mRichLeft as Float = 0.0;
    private var mRichGap as Float = 0.0;

    public var storageX as Float;
    public var storageY as Float;
    public var machineX as Float;
    public var machineY as Float;

    function initialize(areaId as Number) {
        id = areaId;
        unlocked = (areaId == Balance.FOREST);
        machine = new Machine(areaId);
        crew = [] as Array<Actor>;

        var sites = Balance.NODES as Array<Array<Number> >;
        var max = (Balance.NODE_MAX as Array<Number>)[areaId];
        var respawn = (Balance.NODE_RESPAWN as Array<Float>)[areaId];
        nodes = new [sites.size()] as Array<ResourceNode>;
        for (var i = 0; i < sites.size(); i += 1) {
            nodes[i] = new ResourceNode(sites[i][0], sites[i][1], max, respawn);
        }

        var yard = Balance.STORAGE as Array<Number>;
        storageX = yard[0].toFloat();
        storageY = yard[1].toFloat();
        var works = Balance.MACHINE as Array<Number>;
        machineX = works[0].toFloat();
        machineY = works[1].toFloat();

        mRichGap = nextRichGap();
    }

    // ------------------------------------------------------------------ facts

    function name() as String {
        return (Balance.AREA_NAME as Array<String>)[id];
    }

    function resourceName() as String {
        return (Balance.RESOURCE_NAME as Array<String>)[id];
    }

    function nodeKind() as Number {
        return (Balance.NODE_KIND as Array<Number>)[id];
    }

    //! What one unit from here fetches raw, mastery included.
    function unitValue() as Float {
        return (Balance.RESOURCE_VALUE as Array<Float>)[id] * masteryBonus();
    }

    function unlockCost() as Double {
        return (Balance.AREA_UNLOCK as Array<Float>)[id].toDouble();
    }

    function workers() as Number {
        return crew.size();
    }

    function canHire() as Boolean {
        return crew.size() < Balance.WORKER_MAX;
    }

    // ---------------------------------------------------------------- mastery

    function masteryBonus() as Float {
        return 1.0 + Balance.MASTERY_STEP * mastery;
    }

    //! Units needed to go from the current mastery level to the next.
    function masteryTarget() as Float {
        return Balance.MASTERY_BASE
            * Math.pow(Balance.MASTERY_GROWTH, mastery).toFloat();
    }

    function masteryProgress() as Float {
        var target = masteryTarget();
        return (target <= 0.0) ? 0.0 : credited / target;
    }

    //! Count units this area has realised, levelling mastery as they add up.
    //! Division rather than a loop: a long stretch offline can cash in more
    //! than one level at once and a per-level loop would trip the watchdog.
    function credit(units as Float) as Void {
        if (units <= 0.0) {
            return;
        }
        credited += units;
        var gained = 0;
        while (credited >= masteryTarget() && gained < 64) {
            credited -= masteryTarget();
            mastery += 1;
            gained += 1;
        }
        if (gained > 0) {
            syncMastery();
            Events.emit(Events.MASTERY_GAINED, mastery.toDouble());
        }
    }

    //! Push the mastery multiplier into the machine, which prices product
    //! without an Area in hand. Called after anything that moves mastery.
    function syncMastery() as Void {
        machine.valueBonus = masteryBonus();
    }

    // ------------------------------------------------------------ rich veins

    //! True while `index` is the site coming in rich.
    function isRich(index as Number) as Boolean {
        return index >= 0 && index == richNode && mRichLeft > 0.0;
    }

    //! What a hand-worked swing at `index` is worth right now, as a
    //! multiplier on the units taken. Crews never see anything but 1.0.
    function richMultiplier(index as Number) as Float {
        return isRich(index) ? Balance.RICH_MULTIPLIER : 1.0;
    }

    //! How much of the flare is left, 0..1, for the ring around the site.
    function richLeftFraction() as Float {
        if (mRichLeft <= 0.0) {
            return 0.0;
        }
        return mRichLeft / Balance.RICH_SECS;
    }

    private function nextRichGap() as Float {
        var span = Balance.RICH_GAP_SPAN.toNumber();
        return Balance.RICH_GAP_MIN + (Math.rand() % span).abs();
    }

    //! Run the flare clock. Only called for the board the player is on, so an
    //! area nobody is standing in never wastes a vein.
    private function tickRich(dt as Float) as Void {
        if (mRichLeft > 0.0) {
            mRichLeft -= dt;
            // A site that gets worked out mid-flare ends it; there is nothing
            // left to be rich about.
            var node = nodeAt(richNode);
            if (mRichLeft <= 0.0 || node == null || !node.hasStock()) {
                mRichLeft = 0.0;
                richNode = -1;
                mRichGap = nextRichGap();
            }
            return;
        }
        mRichGap -= dt;
        if (mRichGap > 0.0) {
            return;
        }
        var pick = -1;
        var tries = 0;
        while (pick < 0 && tries < nodes.size()) {
            var candidate = (Math.rand() % nodes.size()).abs();
            if (nodes[candidate].hasStock()) {
                pick = candidate;
            }
            tries += 1;
        }
        if (pick < 0) {
            // Whole board is regrowing; try again shortly rather than
            // burning the flare on nothing.
            mRichGap = 5.0;
            return;
        }
        richNode = pick;
        mRichLeft = Balance.RICH_SECS;
        Events.emit(Events.RICH_VEIN, pick.toDouble());
    }

    //! Clear any flare, e.g. when the player walks off this board.
    function clearRich() as Void {
        richNode = -1;
        mRichLeft = 0.0;
        mRichGap = nextRichGap();
    }

    // -------------------------------------------------------------- the board

    function nodeAt(index as Number) as ResourceNode or Null {
        if (index < 0 || index >= nodes.size()) {
            return null;
        }
        return nodes[index];
    }

    //! Nearest node with anything left in it, or -1 if the board is spent.
    function bestNode(fromX as Float, fromY as Float) as Number {
        var best = -1;
        var bestDist = 0.0;
        for (var i = 0; i < nodes.size(); i += 1) {
            var node = nodes[i];
            if (!node.hasStock()) {
                continue;
            }
            var dx = node.x - fromX;
            var dy = node.y - fromY;
            var d = dx * dx + dy * dy;
            if (best < 0 || d < bestDist) {
                best = i;
                bestDist = d;
            }
        }
        return best;
    }

    //! Index of the node under a board-space tap, or -1.
    function nodeUnder(px as Number, py as Number) as Number {
        for (var i = 0; i < nodes.size(); i += 1) {
            if (near(nodes[i].x, nodes[i].y, px, py)) {
                return i;
            }
        }
        return -1;
    }

    function storageUnder(px as Number, py as Number) as Boolean {
        return near(storageX, storageY, px, py);
    }

    function machineUnder(px as Number, py as Number) as Boolean {
        return near(machineX, machineY, px, py);
    }

    function near(ax as Float, ay as Float, px as Number, py as Number) as Boolean {
        var dx = ax - px;
        var dy = ay - py;
        return dx * dx + dy * dy <= Balance.TAP_RADIUS * Balance.TAP_RADIUS;
    }

    // ----------------------------------------------------------------- stores

    //! Raw material dropped off at the yard by any gatherer.
    function deposit(units as Float) as Void {
        stock += units;
        Events.emit(Events.INVENTORY_CHANGED, stock.toDouble());
    }

    //! What the yard would fetch if sold raw right now.
    function stockValue() as Double {
        return (stock * unitValue()).toDouble();
    }

    //! The most this board's nodes can sustain, units/sec, regardless of how
    //! many gatherers are drawing on them - a crew past this point is just
    //! standing around waiting for a node to refill.
    function nodeSupplyRate(regrowBoost as Float) as Float {
        var total = 0.0;
        for (var i = 0; i < nodes.size(); i += 1) {
            var node = nodes[i];
            if (node.respawnSecs > 0.0) {
                total += node.maxQuantity / node.respawnSecs;
            }
        }
        return total * regrowBoost;
    }

    //! Units per second the crew brings in, from their round-trip cycle time.
    //! The same formula prices offline progress, so what the player watches
    //! and what they wake up to agree.
    function crewRate(speed as Float, capacity as Number, collect as Float) as Float {
        if (crew.size() <= 0 || speed <= 0.0 || collect <= 0.0) {
            return 0.0;
        }
        var travel = Balance.OFFLINE_TRIP_PX / speed;
        var work = capacity / collect;
        return crew.size() * capacity / (travel + work);
    }

    //! Cash per minute this board makes on its own: what the crew fetches,
    //! marked up on whatever share of it the machine can keep up with.
    function incomePerMinute(speed as Float, capacity as Number,
                             collect as Float) as Double {
        var raw = crewRate(speed, capacity, collect);
        if (raw <= 0.0) {
            return 0.0d;
        }
        var processed = raw;
        var throughput = machine.rate();
        if (processed > throughput) {
            processed = throughput;
        }
        var loose = raw - processed;
        var perSec = machine.valueOf(processed) + (loose * unitValue()).toDouble();
        return perSec * 60.0d;
    }

    // ------------------------------------------------------------ simulation

    //! Advance the nodes, the crew and the machine. Returns the cash the
    //! machine earned this step, which the caller banks.
    //! `playerHere` says whether this is the board on screen: rich veins only
    //! flare where somebody can walk over and work them.
    function tick(dt as Float, speed as Float, capacity as Number,
                  collect as Float, regrowBoost as Float,
                  playerHere as Boolean) as Double {
        for (var i = 0; i < nodes.size(); i += 1) {
            nodes[i].tick(dt, regrowBoost);
        }
        if (playerHere) {
            tickRich(dt);
        } else if (richNode >= 0) {
            clearRich();
        }
        for (var i = 0; i < crew.size(); i += 1) {
            var worker = crew[i];
            worker.setStats(speed, capacity, collect);
            worker.tick(dt, self);
        }
        return runMachine(dt);
    }

    //! The machine eats from the yard and pays out continuously.
    function runMachine(dt as Float) as Double {
        if (!machine.isBuilt() || stock <= 0.0) {
            return 0.0d;
        }
        var wanted = machine.rate() * dt;
        if (wanted > stock) {
            wanted = stock;
        }
        if (wanted <= 0.0) {
            return 0.0d;
        }
        stock -= wanted;
        machine.absorb(wanted);
        // Priced before crediting, so a level earned by this very batch pays
        // from the next one rather than retroactively.
        var earned = machine.valueOf(wanted);
        credit(wanted);
        return earned;
    }
}
