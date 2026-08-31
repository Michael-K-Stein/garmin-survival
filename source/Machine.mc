import Toybox.Lang;
import Toybox.Math;

//! The machine at the end of an area's trail: a lumber mill, a stone cutter,
//! a smelter, a loom. It pulls raw material out of the yard on its own and
//! turns it into something worth more - the first upgrade in every area that
//! earns money without the player walking anywhere.
class Machine {

    //! Which area this machine belongs to; picks its name, rate and price.
    public var area as Number;
    //! 0 means it has not been built yet.
    public var level as Number = 0;
    //! Raw material banked toward the next visible batch, purely a readout.
    public var batch as Float = 0.0;
    public var made as Number = 0;

    function initialize(areaId as Number) {
        area = areaId;
    }

    function name() as String {
        return (Balance.MACHINE_NAME as Array<String>)[area];
    }

    function product() as String {
        return (Balance.PRODUCT_NAME as Array<String>)[area];
    }

    function isBuilt() as Boolean {
        return level > 0;
    }

    //! Raw units eaten per second at the current level.
    function rate() as Float {
        if (level <= 0) {
            return 0.0;
        }
        var base = (Balance.MACHINE_RATE as Array<Float>)[area];
        return base * (1.0 + Balance.MACHINE_RATE_STEP * (level - 1));
    }

    //! How much more the product is worth than what went into it.
    function valueMultiplier() as Float {
        if (level <= 0) {
            return 1.0;
        }
        return Balance.MACHINE_VALUE + Balance.MACHINE_VALUE_STEP * (level - 1);
    }

    //! What a given amount of raw material is worth once processed.
    function valueOf(units as Float) as Double {
        var raw = (Balance.RESOURCE_VALUE as Array<Float>)[area];
        return (units * raw * valueMultiplier()).toDouble();
    }

    //! Cash per second when the machine is fed continuously.
    function incomePerSecond() as Double {
        return valueOf(rate());
    }

    //! Progress toward the next batch, 0..1, for the bar under the building.
    function batchProgress() as Float {
        if (!isBuilt()) {
            return 0.0;
        }
        return batch / Balance.MACHINE_BATCH.toFloat();
    }

    //! Credit `units` to the batch counter, minting product as batches finish.
    //! Uses division rather than looping per batch: after a long stretch
    //! offline, a leveled-up machine can have thousands of batches to
    //! process at once, and a loop over each one trips the watchdog.
    function absorb(units as Float) as Void {
        batch += units;
        if (batch >= Balance.MACHINE_BATCH) {
            var batches = Math.floor(batch / Balance.MACHINE_BATCH).toNumber();
            batch -= batches * Balance.MACHINE_BATCH;
            var yielded = batches * Balance.MACHINE_YIELD;
            made += yielded;
            Events.emit(Events.MACHINE_COMPLETED, yielded.toDouble());
        }
    }

    //! Cost of building it, or of the next level once it exists.
    function upgradeCost() as Double {
        var base = (Balance.MACHINE_COST as Array<Float>)[area];
        return base * Math.pow(Balance.COST_GROWTH, level).toDouble();
    }
}
