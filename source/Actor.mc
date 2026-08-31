import Toybox.Lang;
import Toybox.Math;

//! The five states every gatherer moves through. The player and the hired
//! workers run the same machine; the only difference is that a worker picks
//! its own target and the player is given one by a tap.
module ActorState {
    const IDLE = 0;
    const MOVE_TO_RESOURCE = 1;
    const COLLECT = 2;
    const MOVE_TO_STORAGE = 3;
    const DEPOSIT = 4;
}

//! A gatherer on the board. Stats are pushed in from GameState every tick so
//! an upgrade takes effect on the very next step, without every actor having
//! to know how upgrade levels turn into numbers.
class Actor {

    public var x as Float;
    public var y as Float;
    public var state as Number = ActorState.IDLE;
    //! Index into the area's node list, or -1 for none.
    public var target as Number = -1;
    public var carry as Float = 0.0;
    //! Workers choose their own work; the player waits to be told.
    public var auto as Boolean;

    public var speed as Float = 40.0;
    public var capacity as Number = 10;
    public var collectRate as Float = 1.0;

    //! Seconds left in a deposit animation, so a drop-off reads as an action
    //! rather than a teleport.
    private var mPause as Float = 0.0;

    function initialize(startX as Float, startY as Float, isAuto as Boolean) {
        x = startX;
        y = startY;
        auto = isAuto;
    }

    function setStats(moveSpeed as Float, carryCapacity as Number, collectSpeed as Float) as Void {
        speed = moveSpeed;
        capacity = carryCapacity;
        collectRate = collectSpeed;
    }

    function isFull() as Boolean {
        return carry >= capacity;
    }

    function fillFraction() as Float {
        if (capacity <= 0) {
            return 0.0;
        }
        return carry / capacity.toFloat();
    }

    //! Send this actor to a resource node. Used by taps on the board.
    function goToNode(index as Number) as Void {
        target = index;
        state = ActorState.MOVE_TO_RESOURCE;
    }

    //! Send this actor home to drop off whatever it is carrying.
    function goToStorage() as Void {
        target = -1;
        state = ActorState.MOVE_TO_STORAGE;
    }

    //! One simulation step. The area owns the nodes and the yard.
    function tick(dt as Float, area as Area) as Void {
        if (state == ActorState.IDLE) {
            if (!auto) {
                return;
            }
            if (isFull() || (carry > 0.0 && area.bestNode(x, y) < 0)) {
                goToStorage();
            } else {
                var pick = area.bestNode(x, y);
                if (pick >= 0) {
                    goToNode(pick);
                }
            }
            return;
        }

        if (state == ActorState.MOVE_TO_RESOURCE) {
            var node = area.nodeAt(target);
            if (node == null || !node.hasStock()) {
                retarget(area);
                return;
            }
            if (stepToward(node.x, node.y, dt)) {
                state = ActorState.COLLECT;
            }
            return;
        }

        if (state == ActorState.COLLECT) {
            var node = area.nodeAt(target);
            if (node == null || !node.hasStock()) {
                retarget(area);
                return;
            }
            // A rich vein pays the player several units per unit actually
            // pulled out of the ground, so it beats the node ceiling instead
            // of just burning through it faster. Crews never get the bonus -
            // being there is the whole reward.
            var bonus = auto ? 1.0 : area.richMultiplier(target);
            var room = capacity - carry;
            var take = collectRate * dt;
            if (take > room / bonus) {
                take = room / bonus;
            }
            take = node.take(take);
            if (take > 0.0) {
                carry += take * bonus;
                Events.emit(Events.RESOURCE_COLLECTED, (take * bonus).toDouble());
            }
            if (isFull()) {
                goToStorage();
            } else if (!node.hasStock()) {
                retarget(area);
            }
            return;
        }

        if (state == ActorState.MOVE_TO_STORAGE) {
            if (stepToward(area.storageX, area.storageY, dt)) {
                state = ActorState.DEPOSIT;
                mPause = 0.35;
            }
            return;
        }

        if (state == ActorState.DEPOSIT) {
            mPause -= dt;
            if (mPause <= 0.0) {
                if (carry > 0.0) {
                    area.deposit(carry);
                    carry = 0.0;
                }
                state = ActorState.IDLE;
            }
            return;
        }
    }

    //! The current node ran dry. Workers find another one; the player heads
    //! home if the trip was worth anything and otherwise waits for a tap.
    private function retarget(area as Area) as Void {
        if (carry > 0.0 && (isFull() || !auto || area.bestNode(x, y) < 0)) {
            goToStorage();
            return;
        }
        var pick = area.bestNode(x, y);
        if (pick >= 0) {
            goToNode(pick);
            return;
        }
        target = -1;
        state = ActorState.IDLE;
    }

    //! Move toward a point at the current speed. Returns true on arrival.
    private function stepToward(tx as Float, ty as Float, dt as Float) as Boolean {
        var dx = tx - x;
        var dy = ty - y;
        var dist = Math.sqrt(dx * dx + dy * dy).toFloat();
        var step = speed * dt;
        if (dist < Balance.ARRIVE) {
            return true;
        }
        if (dist <= step) {
            x = tx;
            y = ty;
            return true;
        }
        x = (x + dx / dist * step).toFloat();
        y = (y + dy / dist * step).toFloat();
        return false;
    }
}
