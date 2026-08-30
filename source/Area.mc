import Toybox.Lang;

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

    function unitValue() as Float {
        return (Balance.RESOURCE_VALUE as Array<Float>)[id];
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
    function tick(dt as Float, speed as Float, capacity as Number,
                  collect as Float) as Double {
        for (var i = 0; i < nodes.size(); i += 1) {
            nodes[i].tick(dt);
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
        return machine.valueOf(wanted);
    }
}
