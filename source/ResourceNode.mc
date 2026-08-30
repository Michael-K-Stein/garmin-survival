import Toybox.Lang;

//! One harvestable site: a tree, a boulder, an ore seam, a stand of flax.
//! The amount left is a Float so a partial second of work is not silently
//! rounded away, and the node refills on a timer once it has been emptied.
class ResourceNode {

    public var x as Float;
    public var y as Float;
    public var quantity as Float;
    public var maxQuantity as Number;
    public var respawnSecs as Float;

    //! Seconds left before the node is stocked again, 0 when it has wood.
    private var mRegrow as Float = 0.0;

    function initialize(px as Number, py as Number, max as Number, respawn as Float) {
        x = px.toFloat();
        y = py.toFloat();
        maxQuantity = max;
        respawnSecs = respawn;
        quantity = max.toFloat();
    }

    function hasStock() as Boolean {
        return quantity > 0.0;
    }

    //! Fraction of a full node left, which sets how big it is drawn.
    function fullness() as Float {
        if (maxQuantity <= 0) {
            return 0.0;
        }
        return quantity / maxQuantity.toFloat();
    }

    //! How far through regrowing an empty node is, 0..1.
    function regrowth() as Float {
        if (hasStock() || respawnSecs <= 0.0) {
            return 1.0;
        }
        return 1.0 - mRegrow / respawnSecs;
    }

    //! Remove up to `amount`; returns what was actually taken.
    function take(amount as Float) as Float {
        var got = amount;
        if (got > quantity) {
            got = quantity;
        }
        if (got <= 0.0) {
            return 0.0;
        }
        quantity -= got;
        if (quantity <= 0.0) {
            quantity = 0.0;
            mRegrow = respawnSecs;
        }
        return got;
    }

    function tick(dt as Float) as Void {
        if (hasStock()) {
            return;
        }
        mRegrow -= dt;
        if (mRegrow <= 0.0) {
            mRegrow = 0.0;
            quantity = maxQuantity.toFloat();
        }
    }

    //! Restore from a save: `left` still in the ground, `regrow` seconds to go.
    function restore(left as Float, regrow as Float) as Void {
        quantity = left;
        if (quantity < 0.0) {
            quantity = 0.0;
        }
        if (quantity > maxQuantity) {
            quantity = maxQuantity.toFloat();
        }
        mRegrow = (quantity > 0.0) ? 0.0 : regrow;
    }

    function regrowLeft() as Float {
        return mRegrow;
    }
}
